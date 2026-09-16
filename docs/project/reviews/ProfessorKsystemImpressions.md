# Impressions from a first teaching pass

*Kind: user review · Status: implemented*

> **Implemented.** Everything below except the four items marked *IGNORE THIS*
> was built on 2026-08-04; `docs/user/guide/ide.md` describes the result and
> `docs/project/plan-of-record.md`'s Status section records it. The list is kept as written,
> because what a first pass asks for is worth having on the record.

A wish list, written after reading `UsingTheIDE.md`, `lps_tutorial.md` and
`lps_summary.md` and then working through three programs in the IDE:
`goat_declarative.pl` (logic, no animation), `blocks3d.lps` (2D and 3D) and
`pddl/rover-p1.pddl` (planning, opened straight from the File menu). Every item is
something noticed while using it. No commentary.

## Running a program

- After a successful run the panes sit at **cycle 1**. Land on the last cycle instead,
  or on the first cycle in which something happened.
- Add `◀` / `▶` step buttons beside the cycle slider. Left/Right arrows currently only
  work when the slider itself has focus.
- Add a **Play** button that walks the cycles at a chosen rate, with Pause. Students
  read a trace by scrubbing; they should not have to drag.
- `Run` has no companion `Step`. Add "run one cycle", "run to cycle N" and "stop".
- The status line says `success after 21 cycles`. Also say *why* it stopped —
  `maxTime` reached, goal satisfied, no more events — and the wall time.
- Show `maxTime` in the toolbar, editable, so a run can be lengthened without editing
  the source.
- A failed run should offer "show me the first cycle that went wrong" rather than only
  a message.
- Cache the previous run and offer a diff of two runs of the same program: students
  change one rule and want to see what that changed.

## The cycle panes

- The pane strip gives no clue which panes have content for this program. Grey out or
  badge the empty ones before the student clicks through all six.
- `2D` and `3D` explain that the program declares no `display/2`. Put the **Animate in
  2D** button *in* that empty pane, not only in the assistant's header.
- **timeline**: mark the currently selected cycle with a vertical line, and let a click
  on the strip move the slider.
- **timeline**: distinguish fluents from events by shape, not only by row; add a legend.
- **state changes**: at cycle 1 it reads "Nothing changed at cycle 1." Say which was the
  next cycle that did change, and link to it.
- **state changes**: group by law (`initiates`/`terminates`/`updates`) with the law's
  source line as the group header.
- **state transitions**: a chain renders as a 187 px column in a 744 px pane. Fit to
  width, and add zoom / pan controls.
- **state transitions**: clicking a state should move the cycle slider to it.
- **internal syntax**: add a Copy button, and make each internal clause link back to the
  surface line it came from.
- Every pane should carry the program name and cycle in its own header — with several
  file tabs open it is easy to lose track of which run is on screen.

## 2D and 3D

- Hover text is the browser's native `title` tooltip: about a second of delay, no
  styling, and it disappears on the smallest movement. Replace it with a small floating
  label that follows the pointer and shows the term *and* its cycle.
- The 3D controls are `+`, `−` and `⤢` with no labels. Give them tooltips, and state
  somewhere which mouse buttons rotate, pan and zoom.
- Add a legend mapping each icon and colour to the fluent it stands for.
- Add "follow this object": keep one object centred as the cycles advance.
- Let a click on an object move the cycle slider to the next cycle in which that
  object's fluent changes.
- Offer a side-by-side 2D view of two adjacent cycles — the before/after is the thing
  being taught.
- Export the current scene as PNG, and the whole run as an animated GIF, for slides.

## Why (the explanation modal)

- Only some nodes of the explanation tree link to source. Link every node that has one,
  and highlight the whole clause rather than putting the caret on its first line.
- The "and why not" row is one unlabelled select and one bare field. Show the accepted
  question forms next to it, with an example.
- Keep a history in the modal: asking a follow-up question loses the previous answer.
- Add a Copy button for the whole explanation — it is the thing a student pastes into
  their notes.
- Let the modal ask about a *different* cycle without closing: a cycle spinner in its
  header.
- From an explanation node, offer "why did this rule not fire earlier".

## Live sessions

- The live feed only ever shows `started live2`, while the header counts up to
  `cycle 13`. Log every cycle: observed events, actions taken, fluents started and
  stopped, with the cycle number.
- The main `2D` pane does not follow a live session — it keeps showing the last batch
  run at cycle 1 while the session runs. Either follow the session, or label the pane
  "showing the last batch run" and offer a button to open the live view.
- The event field takes a term and hints `lps_mousedown(_,_,_)`. Add a dropdown of the
  program's own event templates, filled in and editable.
- Show which mouse events the program actually handles, so the student knows whether
  clicking will do anything before they click.
- Keep a scrollback and let the feed be saved — a live session is otherwise
  unreproducible.
- Show elapsed time and the real cycle rate against the requested one.

## Editor

- IGNORE THIS: The context menu is good; add "explain this rule in English" and "show this
  predicate's callers".
- IGNORE THIS: Occurrence highlighting works on a literal. Add "find all references" as a list.
- Add a gutter mark on every clause that fired during the current run, and shade the
  ones that never fired: dead rules are the commonest student bug.
- Hovering a predicate should show its declaration (`fluents`, `events`, `actions`) and
  its arity.
- In the Edit menu offer a snippet palette for the rule forms — `if … then`, `initiates`, `terminates`,
  `false …`, `observe` — since the syntax is the first barrier.
- A dirty tab should be recoverable: warn on close, and keep unsaved buffers across a
  reload.

## Examples, PDDL and Drools

- The examples dialog is one flat list. Group by directory with headers
  (`pddl/`, `drools/`, `agent/`, `minecraft/`) and mark which entries are conversions.
- Support arrow keys and Enter in that dialog, and remember the last filter.
- Show a one-paragraph description and a preview of the source before opening.
- A `.pddl` file opens as converted LPS. Add a "show the original" toggle, side by side.
- IGNORE THIS:After a planning run, report the plan length and whether it is the shortest found.
- IGNORE THIS:Warn before opening a domain known to search for a long time; offer a search limit in
  the UI rather than only in the source.

## Assistant

- The panel is collapsed and unlabelled at start-up; nothing suggests it exists. Show it
  once, or put a hint in the empty 2D pane.
- The model picker lists the provider's whole catalogue in name order, so a 4096-token
  model appears first. Put the models known to work at the top under their own heading.
- Show which provider key is in use, and say so plainly when none is.
- Let a generated `display/2` block be applied to the buffer *and* previewed in the 2D
  pane before accepting.

## Help and orientation

- Add a keyboard-shortcut list to the Help menu. There is currently no way to discover
  them.
- Add a short guided tour in docs/: open an example, run it, look at three panes, ask one "why".
- Link each pane's header to the section of `UsingTheIDE.md` that describes it.
- The Help documents open in a new tab, losing the workspace. A docked documentation
  pane beside the editor would suit a class better.
- State the version and build date somewhere visible; "About LPS2" is the only place to
  look and students will be running different builds.
