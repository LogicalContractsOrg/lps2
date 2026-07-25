# The LPS(2) IDE (M9, M10)

`./lps ide` serves a web IDE on `http://localhost:3060/`. It is a client of the
same single HTTP endpoint everything else uses (`src/edges/lps_http.pl`), so
anything it does can be done from `curl`, and nothing it does needs engine
knowledge it does not get over the wire.

```sh
./lps ide                  # http://localhost:3060/
./lps ide --port 8080
```

## What it shows

| pane | plan | fed by |
|---|---|---|
| editor + diagnostics | §I.10.1 | `analyse` — debounced 1500 ms, then a server round trip |
| timeline | §I.10.2 | `timeline` — one lane per fluent, with intervals |
| state changes | §I.10.3 | `changes` — what was initiated, terminated, persisted, and **which causal law fired** |
| state transitions | upstream's `godfa/1` | `automaton` — the run as a finite automaton |
| animation | §I.10.4 | `scene` — the program's own `display/2` clauses, scrubbed by cycle |
| explain | §I.10.5 | `explain` — the five question forms |

Every one of them is a *reading of the trace* the engine already emits (§I.5.2).
Nothing is re-run and nothing is re-derived to answer a question, which is what
makes the answers worth trusting: if the engine did not record it, the IDE says
so rather than reconstructing something plausible.

## Two state diagrams, and why they are two

**State changes** is per *cycle*: at cycle 7, these fluents were initiated by
this action under that causal law, these terminated, these persisted. It
answers "what happened just now".

**State transitions** is per *state*. Every distinct set of fluents the run
passed through is one node, however many times the run visited it, and the
events and actions that moved between them are the edges. It answers "what
shape is this program".

The difference matters exactly when a program *revisits* a state.
`bankTransfer.pl` has two accounts passing ten and twenty back and forth for
ten cycles; the state-change diagram is eleven near-identical frames, and the
transitions diagram is six states with a loop, which is what the program
actually is.

This is upstream's `godfa/1` (`legacy_lps1/utils/visualizer.P`,
`dfa_graph/4`), and four of its decisions are reproduced deliberately:

- **Cycle 0 is dropped.** Upstream calls this "a hack to discard irrelevant
  state information". It is, and it is the right hack: the emission at time 0
  is the program's `initially`, before any rule has run, and keeping it puts a
  phantom state and a phantom transition at the head of every diagram.
- **A cycle with no fluents is still a state** — the empty one — so a run that
  empties the store does not silently lose a node.
- **A node is identified by the set of cycles it was visited at.** That is what
  makes two visits one node.
- **Events and actions are told apart, and coloured differently** (orange and
  green, upstream's colours): something happened *to* the program, versus the
  program *did* something. An occurrence that is both a declared action and an
  observed event counts as an event — the observation is the evidence.

Two options, also upstream's:

| option | what it does |
|---|---|
| abstract numbers | every number becomes `n`, so a program whose states differ only in an amount collapses to a diagram about its shape. For `bankTransfer` that is the difference between six states and sixty. |
| hide self-loops | drop transitions that do not change the state — useful when a polled event fires every cycle and would otherwise bury the real transitions |

From the CLI:

```sh
./lps automaton legacy_lps1/examples/CLOUT_workshop/bankTransfer.pl
./lps automaton PROGRAM --abstract-numbers --non-reflexive
```

Back-edges are routed around the right-hand margin rather than drawn on top of
the forward edge between the same pair of states, because for a program that
oscillates that pair is *every* pair.

## The five question forms (§I.10.5)

```
why(happened(A), T)       the rule/goal chain that produced the action
why(holds(F), T)          the last initiating event, or persistence since T'
why(stopped(F), T)        the terminating event and its cause
why_not(happened(A), T)   four answerable cases, and an honest fallback
what_if([E1,E2], T)       fork at T, inject, replay, diff the traces
```

From the command line:

```sh
./lps explain legacy_lps1/examples/goat.pl --ask "why(happened(row(south,north)), 2)"
./lps timeline legacy_lps1/examples/goat.pl
./lps changes  legacy_lps1/examples/goat.pl --at 2
```

`why_not` is the one the plan calls "the hard one, and the most useful". It
distinguishes four cases, each read from a record the engine makes:

| verdict | means |
|---|---|
| `no_goal_created` | no reactive rule ever fired with this action in its consequent |
| `blocked_by_denial` | a goal existed, but a `false` clause blocked the action — the clause is named |
| `rejected_by_prospective_constraint` | the state the action *would have produced* was rejected — the constraint is named |
| `no_plan_found` | under `lps_engine(planning)`, no plan within the horizon |
| `no_applicable_rule` | none of the above. Reported plainly rather than dressed up |

`tools/explain_test.pl` is the M9 gate and covers all five forms and all four
`why_not` cases.

## The visual mapping (§I.10.4)

The animation is driven by `display/2`, which already exists in the corpus —
ten programs declare one — so the mapping is a reading of something the
programs already have rather than a new language feature:

```prolog
display(location(P,L), [type:ellipse, label:P, point:[PX,PY],
                        size:[20,40], fillColor:green]) :-
    locationXY(L,X,Y), PY is Y+10, (P=dad -> PX is X+25 ; PX is X+50).

display(timeless, Divisions) :- findall([type:rectangle, ...], ..., Divisions).
```

Shapes understood: `rectangle`, `ellipse`, `circle`, `arrow`, `raster`, with
`point`/`position`/`center`/`from`/`to`, `size`, `radius`, `label`, `fillColor`,
`strokeColor`, `scale`, `source`, `fontSize`. A `display(timeless, _)` clause is
the backdrop. Scrubbing the cycle slider asks the server for a different
cycle's scene; interpolation between two scenes is the front end's business,
which is why it is CSS and not a physics.

`legacy_lps1/examples/CLOUT_workshop/badlight.pl` is the example to try: four
rooms, two people and some light bulbs.

## What this is not

**It is not the LE2 Monaco editor.** §I.10.1 says to extend it, and that
repository is not available here. What is built instead is a self-contained
page using the pattern LE2 uses — a debounce, then a server-side analysis,
because with WASM deferred the analysis cannot run locally — and the operations
an LSP worker would call. Swapping the `<textarea>` for Monaco is then a
front-end change and not a protocol change; the server side is already the
shape an LSP needs, with diagnostics carrying `src(File, Line, Col, Kind)`
positions rather than printed text (§I.2.5).

**The rendering has been checked in a browser.** `tools/ide_screenshots.cjs`
drives the four panes with Playwright (Chromium), captures each one, and — more
usefully than the pictures — fails on any console error, page error or failed
request, so a pane that silently renders nothing is caught rather than admired.

```sh
./lps ide --port 3060 &
NODE_PATH=/usr/lib/node_modules node tools/ide_screenshots.cjs build/ide-shots 3060
```

Looking at it found four things that every non-visual check had passed:

- the sample program embedded in the page had a doubled backslash — `O1 \\= O2`
  — from escaping Prolog inside a JavaScript template literal inside HTML. It
  did not parse. Examples are now *served* by the endpoint (`example`
  operation), which removes the escaping layer entirely;
- the editor reported **"no errors" for a program that had not parsed**, because
  a thrown analysis returns no `diagnostics` field and the page treated a
  missing field as an empty one. That is the one failure mode an editor must
  never have;
- shapes anchored on a boundary were clipped, because the viewBox was measured
  from anchor points rather than extents — and boundaries are exactly where the
  interesting objects sit;
- labels were drawn under later shapes and inside filled ones, so `livingroom`
  read as `livingro` and green-on-green was unreadable. Labels are now drawn
  last, with a halo.

A fifth was a gap rather than a bug: under planning mode an explanation had
nothing to point at, because a planned action has no reactive rule behind it
and no composite-event ancestry. The plan is the provenance there, so it is
recorded, and "why did A not happen?" now answers
`scheduled_for_another_cycle` with the step and cycle.

**`display/2` is evaluated by calling the program**, so a clause with a
side-effecting body will have that effect once per scene request. That is the
program's business, but worth knowing before pointing the scrubber at one.
