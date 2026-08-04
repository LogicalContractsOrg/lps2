# Using the LPS2 IDE

`./lps ide` serves it on <http://localhost:3060>. This document is what each
part of it does, followed by a **[how do I …](#how-do-i-)** section that answers
the questions people actually arrive with.

The IDE is a client of `/lpsapi` and of nothing else, which is the rule the
whole design is held to: **if the editor can do it, `curl` can do it.** Nothing
below is a feature of the editor alone.

![The IDE](images/ide-overview.png)

---

## Contents

- [The layout](#the-layout)
- [The editor](#the-editor)
- [The seven panes](#the-seven-panes)
- [Asking why](#asking-why)
- [The assistant](#the-assistant)
- [Live sessions](#live-sessions)
- [The menus](#the-menus)
- [How do I …](#how-do-i-)
- [Keyboard](#keyboard)

---

## The layout

Four regions, all resizable, all remembered between visits.

| region | what it is |
|---|---|
| **file tabs** | one tab per open file. A tab owns its *run* as well as its text |
| **editor** | Monaco, with one grammar for LPS and the Prolog inside it |
| **assistant** | a language model with the same tools you have. Collapsed by default |
| **live session** | a program that keeps cycling and takes events. Collapsed by default |
| **panes** (right) | seven readings of the run belonging to the lit tab |

Drag the vertical bar between editor and panes; drag the horizontal bars above
the assistant and the live panel. Double-click the vertical one to centre it.

**Tabs own runs.** Open two programs, run both, and switching tabs switches
everything on the right — timeline, scene, cycle, diagnostics. A tab with a run
carries a green dot. That is how you compare two versions of a program: open
both, run both, and flip.

## The editor

Diagnostics appear **in the text**, not in a strip below it: a squiggle on the
line, the message on hover, a mark in the overview ruler on the right edge of
the scrollbar. The count in the top bar is a button — click it to jump to the
first problem, **F8** for the next.

![A program that does not parse](images/ide-diagnostics.png)

Analysis runs about a second after you stop typing, on the server, and reports
what the compiler reports. A file that does not parse still gets everything the
reader could determine before it gave up.

**Right-click** in the text for the context menu:

| item | |
|---|---|
| Run | compile and run — the same as Ctrl/Cmd + Enter |
| See internal syntax | what the engine actually runs (§I.3) |
| Why did this happen? | explain the term under the cursor at the current cycle |
| Observe this (live session) | send the term under the cursor as an event |
| Show definition | jump to the first clause head with that name |
| Go back | return to where you jumped from |
| Show occurrences | every use, as a list you can click |
| Fold / unfold all clauses for this predicate | |
| Copy URL | a link that carries the program in its fragment |

Also there: cut, copy, paste, and everything Monaco brings — **Ctrl/Cmd + F**
to find, **Ctrl/Cmd + H** to replace, multi-cursor, line moves, comment
toggling. Selecting a term highlights its other occurrences, and so does
resting the cursor on a name.

Completion offers the language's own vocabulary *and* this program's: the
events and actions it declares, taken from the last analysis.

## The seven panes

All seven scrub together on one cycle slider.

**timeline** — one lane per fluent over the interval it holds, then the events
of each cycle, then composite events. Click the picture to move the cycle.

![The timeline](images/ide-timeline.png)

**state changes** — what was initiated, terminated and updated at this cycle,
what caused it, and *which causal law* did it, as a line number in your file.
Everything unchanged is listed separately as *persisted*, because the engine
knows the difference between "still true" and "made true again".

![State changes](images/ide-changes.png)

**state transitions** — the run as an automaton, every distinct state once, so
a program that revisits a state reads as a loop. A run whose states form a
simple chain is laid out as a column; anything that branches goes left to
right. Two toggles: *abstract numbers* collapses states differing only in a
number, *hide self-loops* drops the arcs a state makes to itself.

![The state-transitions diagram](images/ide-automaton.png)

**2D** — the `display/2` visual mapping. Origin bottom left, y upward. Wheel to
zoom, drag to pan, double-click to reset.

**3D** — `display3d/2`, on three.js. Drag to orbit, wheel to dolly, ⤢ to return
to the camera the program declared. The view survives moving the cycle slider:
the declared camera is a *starting* camera, not a per-frame instruction.

**internal syntax** — `reactive_rule/2`, `d_pre/1`, `updated/4`,
`initial_state/1`. Worth looking at once: it makes clear that `false X, Y, Z` is
a denial and that `at`/`from`/`to` are sugar over explicit time arguments.

## Asking why

There is no explain pane. **Right-click anything a pane drew** — a timeline
bar, an event dot, a row of the changes table, a state box, an edge label, a
shape in 2D, a solid in 3D — and you get the explanation for that term at that
cycle.

The modal also has a **why not** field, because the interesting question is
often about a term that is *absent* and you cannot click on something that was
not drawn. It is prefilled with the shape; edit it and press the button.

`why_not` has four different answers and they are not interchangeable:

- **scheduled_for_another_cycle** — the plan does intend to, later, as step *n*.
- **no_goal_created** — nothing ever asked for it.
- **rejected_by_prospective_constraint** — something asked, and a named denial
  refused it.
- **no_plan_found** — asked for, and no plan within the horizon.

Outside those the answer is an honest "no applicable rule". Where the trace
recorded nothing, the pane says *not recorded* rather than reconstructing
something plausible — which is the whole value of it after an incident.

## The assistant

A language model with the same tools you have: it compiles, runs, asks why, and
checks what its own display clauses drew. Its idea of "this compiles" is the
editor's, because it is the same call.

Choose a model in the panel header for one question, or set the default in
**Misc ▸ API keys, models & Assistant settings**. The list is what the providers
themselves report — read once when the server starts, and again whenever you
press *Re-read from providers*. A key in the server's environment wins over one
typed into the browser.

Two buttons do a canned job:

**Animate in 2D** asks the model for a *plan* — which containers exist, what
moves between them, which fluent puts a thing in a container, what each thing
looks like — and then computes the geometry itself. The model never writes a
coordinate. That is why the result does not overlap:

![Animate in 2D](images/ide-assistant-2d.png)

The generated clauses are ordinary Prolog over a `lps_slot/4` table. Move a slot
and everything that ever sits in it moves.

**Animate in 3D** is the same idea with less machinery behind it: the model
writes `display3d/2` directly and then uses the `scene` tool to check that
nothing is invisible.

Nothing is applied to your buffer until you press **Apply to editor**, and it is
one undo away.

## Live sessions

Drop `maxTime` and a program runs until it is stopped, doing nothing until an
event arrives.

![A live session](images/ide-live.png)

- **every N ms** — the cycle rate. The engine's own time is still computed from
  the cycle number; this is a pacing loop at the edge.
- **Send** — an event term. The placeholder is one of *this* program's declared
  events.
- **Translate** — say it in English and let the assistant pick the term. It is
  shown before it is sent, because a mistranslated observation is an
  observation you did not make.
- **2D / 3D** — a window that follows the running session rather than scrubbing
  a finished one. Disabled, with a reason, when the program has no display
  clauses.

Events arriving mid-cycle are delivered at the next boundary; the feed says
*queued for cycle N* so you know where to look.

**A program that defines `lps_mousedown/3`, `lps_mouseup/3` or
`lps_mousedrag/3` can be clicked on.** The live 2D and 3D windows inject those
events in the program's own scene coordinates. A program that does not define
them gets no listener at all. `examples/lights.lps` is the demonstration.

## The menus

**File** — New, Open (several at once), Open example from server (every program
on the server, filterable, with a resizable name column), Save, Save As, Close
file, Copy share link.

`.pddl` and `.drl` files open like any other: the server converts them to LPS
and the tab carries a header saying what it was converted from and when.

**Edit** — undo/redo, find, replace, go to line, comment toggling, collapse all
clauses, expand all, next problem.

**Misc** — theme (dark, light, high contrast), font size, API keys and models,
the server token, and *Deploy as WASM*.

**Help** — this document, the tutorial, the language reference, the tour, the
icon licences, and About.

---

## How do I …

**…run a program?** Ctrl/Cmd + Enter, or the Run button. The panes fill in.

**…see why something happened?** Right-click it in any pane.

**…see why something *didn't* happen?** Right-click anything, then edit the
*why not* field in the modal that opens.

**…compare two programs?** Open both (File ▸ Open takes several, or the + on
the tab strip), run both, and switch tabs. Each tab keeps its own run.

**…find where a predicate is defined?** Right-click it ▸ Show definition, or
Ctrl/Cmd + F12. *Go back* returns you.

**…give my program an animation?** Press *Animate in 2D*. Or write `display/2`
clauses yourself — `docs/lps_summary.md` has the property list.

**…use one of the built-in icons?** `[type:raster, icon:NAME]`. Help ▸ About the
icons lists every name, with a picture.

**…feed a program events while it runs?** Open the Live session panel and press
Start. Type an event term, or say it in English and press Translate.

**…make an animation clickable?** Declare `lps_mousedown/3` (and/or `lps_mouseup/3`,
`lps_mousedrag/3`) as events and write a rule that reacts to them. Then open the
live 2D window and click. See `examples/lights.lps`.

**…run a PDDL problem?** File ▸ Open, and select the domain *and* the problem
together. They arrive as one LPS buffer with `achieve` at the end.

**…run a Drools rule base?** File ▸ Open the `.drl`. Edit the generated
`initial_state([])` to put some facts in working memory, and run.

**…write my program in English?** That is Logical English, and it lives in LE2:
`the target language is: lps.` at the top of a `.le` file. See
`docs/deploy.md` for running the two servers side by side.

**…share a program?** File ▸ Copy share link. The program travels in the URL
fragment, so nothing is uploaded.

**…run a program with no server at all?** Misc ▸ Deploy as WASM. You get one
HTML page with the engine and your program in it. The dialog explains what it
still fetches and how to serve it.

**…point the IDE at a different LPS2 server?** `window.LPS_API_BASE` before the
bundle loads, or serve the page from that server. LE2's editor takes
`?lpsapi=…` in the query string.

**…get rid of the "no LLM key configured" state?** Misc ▸ API keys. Or start
the server with `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GROQ_API_KEY`,
`GEMINI_API_KEY` or `TOGETHER_API_KEY` in its environment, which takes
precedence.

**…make the 3D scene stop resetting when I scrub?** It does not any more. If
you want the declared camera back, press ⤢.

**…read the diagnostics when the strip is gone?** They are on the line: hover
for the message, F8 to walk them, click the count in the top bar for the first.

---

## Keyboard

| | |
|---|---|
| Ctrl/Cmd + Enter | run |
| Ctrl/Cmd + F | find |
| Ctrl/Cmd + H | replace |
| F8 | next problem |
| Ctrl/Cmd + F12 | show definition |
| Ctrl/Cmd + / | toggle line comment |
| Alt + ↑/↓ | move line |
| Shift + Alt + ↑/↓ | duplicate line |
| Ctrl/Cmd + D | select next occurrence |
| Escape | close a dialog |
| Middle-click a tab | close that file |
