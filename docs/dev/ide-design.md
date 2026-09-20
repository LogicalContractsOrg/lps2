# The editor: a design record

*Kind: design record · Audience: developers · Status: 2026-08-20 (the user guide is docs/user/guide/ide.md)*

> **This is not the user guide.** [`UsingTheIDE.md`](../user/guide/ide.md) describes
> the editor as it is now, and [`glossary.md`](../user/reference/glossary.md) defines the terms.
>
> **This document is kept for two things.** First, it says what each pane is a
> reading of, which the user guide does not go into. Second, its `display/2`
> section compares this renderer with LPS1's shape by shape, and that comparison
> is written down nowhere else.

`./lps ide` serves the editor on `http://localhost:3060/`. It is a client of the
same single web address everything else uses (`src/edges/lps_http.pl`), so
anything it does can be done from `curl`, and nothing it does depends on
knowledge of the engine that it does not get over the network.

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
| state transitions | LPS1's `godfa/1` | `automaton` — the run as a finite automaton |
| animation | §I.10.4 | `scene` — the program's own `display/2` clauses, scrubbed by cycle; or, with *Scenes* in the pane's toolbar, `scenes` — one picture per keyframe, the whole run as a strip (AnimationPlan §7) |
| explain | §I.10.5 | `explain` — the five question forms |

One more operation feeds no pane of its own but three of them at once:
`focus` — the fluents that tell the run's states apart, the cycles worth a
picture and the states it comes back to (`lps_scene_focus/3`, AnimationPlan
§5). The scene panes seek by it, the slider's marks are it, the strip is keyed
on it, and the assistant is given it before it plans a picture — so none of
those four can disagree about what mattered in a run.

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

This is LPS1's `godfa/1` (`legacy_lps1/utils/visualizer.P`,
`dfa_graph/4`), and four of its decisions are reproduced deliberately:

- **Cycle 0 is dropped.** LPS1 calls this "a hack to discard irrelevant
  state information". It is, and it is the right hack: the emission at time 0
  is the program's `initially`, before any rule has run, and keeping it puts a
  phantom state and a phantom transition at the head of every diagram.
- **A cycle with no fluents is still a state** — the empty one — so a run that
  empties the store does not silently lose a node.
- **A node is identified by the set of cycles it was visited at.** That is what
  makes two visits one node.
- **Events and actions are told apart, and coloured differently** (orange and
  green, LPS1's colours): something happened *to* the program, versus the
  program *did* something. An occurrence that is both a declared action and an
  observed event counts as an event — the observation is the evidence.

Two options, also LPS1's:

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
seventeen programs declare one — so the mapping is a reading of something the
programs already have rather than a new language feature:

```prolog
display(location(P,L), [type:ellipse, label:P, point:[PX,PY],
                        size:[20,40], fillColor:green]) :-
    locationXY(L,X,Y), PY is Y+10, (P=dad -> PX is X+25 ; PX is X+50).

display(timeless, Divisions) :- findall([type:rectangle, ...], ..., Divisions).
```

A scene is the set of `display/2` answers for one cycle's fluents and events,
plus the `display(timeless, _)` backdrop, computed by `lps_display_scene/4`
(`src/core/lps_explain.pl`) against that cycle's state and served by the `scene`
operation. Scrubbing the cycle slider asks the server for a different cycle's
scene; interpolation between two scenes is the front end's business, which is
why it is CSS and not a physics.

`legacy_lps1/examples/CLOUT_workshop/badlight.pl` is the example to try: four
rooms, two people and some light bulbs.

### What is supported, against the old paper.js renderer

The old animation was a SWISH answer renderer: `swish/lps_2d_renderer.pl` plus
682 lines of `swish/web/lps/2dWorld.js`, drawing on a canvas with
[paper.js](http://paperjs.org). Its language is documented in
`legacy_lps1/swish/2dWord.md`, and its defining property is that **props were
handed almost verbatim to paper.js constructors** — hence that document's "in
general, any property accepted in a `Path` constructor will work".

LPS2 draws **SVG in about sixty lines** (`src/ide/index.html`, `drawShape`)
with no graphics dependency at all. So the *language* is the same declarative
`display/2` — same subjects, same `type:`/prop lists, same `timeless` backdrop —
and what differs is how much of paper.js's surface survives. The deliberate
trade is one self-contained page with no build step (which is also what keeps
the container in `docs/dev/deploy.md` small) against fidelity on the richer shapes.

| `type:` | then (paper.js) | now (SVG) |
|---|---|---|
| `rectangle` | `Path.Rectangle`, from `from`/`to` **or** `point`+`size`, `radius` for round corners | `<rect>`, **only** from `from`+`to`; the `point`+`size` form falls through to the ellipse case |
| `circle` | `Path.Circle` | `<circle>`, `point`/`position`/`center` + `radius` |
| `ellipse` | `Path.Ellipse` | `<ellipse>`, anchor + `size` |
| `arrow` | custom group: shaft plus head, `biDirectional` for a second head | `<line>` with an arrowhead marker; `biDirectional` ignored |
| `raster` / `image` | `Raster` from `source`, `scale` | `<image>`, plus a dot underneath so a dead link still shows a position — the corpus has dead links |
| `star`, `regularPolygon`, `line`, `arc`, `path`, `pointtext`/`text` | native paper.js constructors (`radius1`/`radius2`/`points`, `segments`, `content`) | **not drawn as such.** Anything with an anchor point degrades to an ellipse of `size` (default 20×20); anything with neither an anchor nor `from`+`to` is skipped |

Corpus usage, for scale: 23 `rectangle`, 15 `ellipse`, 14 `star`, 9 `circle`,
6 `arrow`, 5 `raster`, 4 `line`, 5 `text`/`pointText`, and one each of
`regularPolygon`, `path` and `arc`. So the shapes that degrade are not exotic —
`star` is the third most used type in the corpus.

Props read: `type`, `from`, `to`, `point`/`position`/`center`, `size`, `radius`,
`scale`, `source`, `label`, `fillColor`, `strokeColor`, `fontSize`. Ignored:
`id`, `sendToBack`/`bringToFront`, `opacity`, `strokeWidth`, `shadowColor`,
`shadowOffset`, `radius1`/`radius2`/`points`, `segments`, `content`, `transform`,
`strokeCap` — and, of course, the "any paper.js property" escape hatch, which
has no meaning without paper.js.

Four differences that are not about shapes, and matter more:

- **The y axis is not flipped.** paper.js ran with an inverted view matrix, so
  the old origin is **bottom left** (`2dWord.md`, and the `matrix.d = -1` fixups
  in `2dWorld.js` that keep rasters and text upright under it). The SVG pane
  uses SVG's own top-left origin, so a scene laid out for the old renderer comes
  out **vertically mirrored**. Fixing it means a flip transform on the group plus
  a counter-flip on every label — exactly the fixup paper.js needed — and would
  invalidate the current screenshots, so it is a deliberate open item rather than
  an oversight.
- **Every matching clause draws.** LPS1 considers *only the first* display
  spec found for a fluent or event; `subject_visuals/4` collects all solutions,
  so a nondeterministic `display/2` draws one object per solution.
- **`timeless` must be a list of lists.** The scene layer maps over the timeless
  spec as a list of objects, which is how every live corpus program writes it.
  The flat single-object form `2dWord.md` also allows — `display(timeless,
  [type:rectangle, from:…, to:…])`, as in the commented-out block of
  `bubbleSort.pl` — is read as a list of props rather than a list of objects and
  silently draws nothing. A one-clause normalisation in `props_dict/2` would
  close it.
- **Interactive mode is **done** (§I.10.4d): `lps_mousedown/3`, `lps_mouseup/3` and `lps_mousedrag/3` are injected from a live 2D or 3D window into any program that declares them — see docs/user/reference/lps.md §18b and examples/start/lights.lps.** The old renderer had two: *eager*
  (postmortem, the whole history) and *lazy* (`server/1`, one cycle at a time in
  real time), with play/pause/step controls, alt-click to suspend the run, and
  mouse input fed back into the program as `lps_mouseup/3`, `lps_mousedown/3`
  and `lps_mousedrag/3` events — see `badlight_user.pl` and `life_lazyGUI.pl`.
  LPS2 has the postmortem mode only: scrub a finished trace. Nothing in the
  engine blocks the rest (a session is steppable and `lps_session_observe/3`
  takes events), but no surface exposes it, so the two GUI-input corpus programs
  compile and run without their interactivity.

Finally, the animation pane exists **only in `src/ide/`**. LE2's `editor/lps.html`
carries timeline, state changes, state transitions and internal syntax; it has no
scene pane, so `display/2` is one of the few things the reference client does that
the LE2 editor does not.

## What this is not

> **Superseded, August 2026.** This section describes the M9/M10 IDE, which is what
> exists. The plan now has LPS2 growing its own full Monaco editor (M14), real Konva
> and three.js renderers (M15) and an assistant (M16) — see
> [`LPSplusLLM.md` §I.10.1a, §I.10.4a and §I.10.6](../project/plan-of-record.md#i106-the-lps-assistant-m16).
> The reasoning below for *why* `src/ide/` stayed plain is the reasoning that decision
> reverses; the constraint it protected — that `/lpsapi` is the only channel, so anything
> the editor does is reachable with `curl` — survives it.

**It is not the LE2 Monaco editor** — deliberately, and no longer for want of
one. §I.10.1 says to extend LE2's editor, and M8e did: `editor/lps.html` there is
Monaco with two language modes and two backends. This page is a self-contained
`<textarea>` using the same pattern — a debounce, then a server-side analysis,
because with WASM deferred the analysis cannot run locally — and it is kept as
the API's *reference client*, so that `/lpsapi` stays independently testable with
no LE2 dependency in this repository's CI. That the two front ends were built
against the same operations is the evidence the protocol is a protocol: the
server side is the shape an LSP needs, with diagnostics carrying
`src(File, Line, Col, Kind)` positions rather than printed text (§I.2.5).

**The rendering has been checked in a browser.** `tools/ide_screenshots.cjs`
drives the six panes with Playwright (Chromium), captures each one, and — more
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
