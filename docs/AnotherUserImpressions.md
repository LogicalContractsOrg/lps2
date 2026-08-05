# Another user's impressions — driving the IDE cold

> **Implemented on 2026-08-05**, everything below except the two items struck
> through as mistakes of my own. `docs/UsingTheIDE.md` describes the result,
> `docs/lps_summary.md` §18 the new plan shape, and `docs/LPSplusLLM.md`'s Status
> section records it. The list is kept as written, because what a cold first pass
> asks for is worth having on the record even where it was wrong.

A second pass over the same ground as `ProfessorKsystemImpressions.md`, done on
2026-08-05 by driving `./lps ide` with Playwright rather than by reading the
documentation: open a program, press things, look at what the screen says.
Programs used: `goat_declarative.pl` (logic, no animation), `lights.lps` (2D and
mouse input), `blocks3d.lps` (3D), `thermostat.lps` (waits for the world), plus a
deliberately broken buffer. The assistant was exercised with a real Groq key.

Everything below was observed, not inferred. Nothing here is a code change.

---

## The three that account for most of the confusion

### 1. After a successful run the pane strip still says "run the program first"

A pane tab loses its `unavailable` class **only when it is clicked**, not when a run
produces content for it. So immediately after `Run` succeeds, all five tabs are at
opacity 0.45 with the tooltip *"run the program first"* — including `timeline`, which
is showing a full timeline at that very moment. Measured on `blocks3d.lps`: dimmed at
+1 s, +3 s, +6 s, +10 s after a successful run; they turn solid one by one as you visit
them.

`ProfessorKsystemImpressions.md` asked for exactly this affordance ("grey out or badge
the empty ones before the student clicks through all six") and it was built — but it is
wired to *visited* rather than to *has content*, so it now says the opposite of the
truth precisely when the panes are ready. This is, on its own, a complete explanation of
"non-intuitive panels": the UI tells every new user that nothing works.

**Fix:** derive `unavailable` from the run result (has a session? has scene data? has
`display/2`?), and use three states, not two — *no run yet* / *nothing for this program*
/ *ready*. Keep the tooltips distinct: "run the program first" and "this program
declares no `display/2` clauses" are different sentences and should never both be a grey
tab.

### 2. "Animate in 2D" is a four-step flow, and the pane you pressed it in never changes

The honest sequence, timed:

1. In the empty **2D** pane, press **Animate in 2D**. The pane keeps saying *"This
   program declares no display/2 clauses"*, with the same button still inviting a press.
   Nothing anywhere in the viewport indicates that work has started.
2. The only sign of life is the word *thinking…* in the assistant dock at the bottom
   **left** — the far corner from where the click happened.
3. ~3 s later the reply lands. The dock is 123 px tall showing 275 px of text and is
   scrolled to 45 of a possible 152, so the two buttons the whole flow depends on —
   **Show the change** and **Apply to editor** — are *below the fold* and the log did
   not scroll to them. The visible text is cut mid-sentence ("…Edit a").
4. Press **Apply to editor**. The buffer now genuinely contains `display/2`
   (+1723 chars, verified). The 2D pane *still* says "This program declares no display/2
   clauses". Status says "assistant edit applied — undo with Ctrl/Cmd+Z".
5. Press **Run** by hand. Only now does the canvas appear — and it is very good
   (title, two labelled banks, icons for wolf/goat/cabbage/farmer).

So: press, scroll, apply, run — with the pane actively contradicting the state of the
buffer for two of those steps.

**Fix:** run the animate flow *inside* the pane that asked for it (spinner in the pane,
"the assistant is drawing this…"); auto-scroll the assistant log to its action buttons,
or promote Apply/Show into the pane; and after an assistant edit, either re-run
automatically or replace the empty-state text with "the program changed — press Run"
rather than a stale claim about `display/2`.

### 3. Two ways to run, on opposite corners, showing different truths at once

`Run`/`Step` live top-right; **Live session ▸ Start** lives bottom-left in a dock. They
are different executions of the same file and the screen shows both at once. Observed on
`lights.lps`: the live dock read *"cycle 7 · running · 3 s"* while the top-right status
read *"success after 21 cycles"* and the timeline pane showed the batch run at cycle 20.
Nothing marks which of the two the viewport belongs to.

Worse, the live 2D view is a **separate browser window** (`/live-view.html?live=…&kind=2d`),
opened by a `2D` button in the live dock — while a `2D` *tab* already exists in the
viewport showing something else. Two controls labelled "2D", one interactive, one a
replay. `lights.lps`'s own header comment has to spell the ritual out ("Live session ▸
Start … press 2D … click the lamps in the window that opens"), which is the tell.

**Fix:** one run model in the UI. Either the live session drives the same viewport
(panes update as cycles arrive) or the viewport is visibly labelled "batch run" vs "live
session". At minimum, don't have two differently-behaved controls both called `2D` on
the same screen.

---

## Panes

- **state changes opens on the last cycle, which is usually the empty one.** On
  `goat_declarative`, cycles 2–8 have content and 0, 1, 9, 10 do not; the pane opens at
  cycle 10 and says *"Nothing changed at cycle 10."* First impression: broken pane. The
  earlier impressions doc asked for "say which was the next cycle that did change, and
  link to it" — still open. Better still: mark the cycles that changed on the slider
  itself, so scrubbing has landmarks.
- **Some programs never change anything in a batch run, and nothing says so.** On
  `lights.lps` and `thermostat.lps` the changes pane reads "Nothing changed at cycle N"
  for *every* cycle (21 of 21, both). That is correct — these programs only do anything
  with injected events — but a user cannot tell "correct and empty" from "broken". A
  run that produced no events at all deserves a sentence: *"nothing happened: this
  program waits for events — try Live session."*
- **The pane header is shown on panes it cannot act on.** The transport (⏮ ◀ ▶ ▶| ⏭),
  the cycle slider, the cycle label and the hint *"right-click anything to ask why it
  happened"* are all rendered above **internal syntax** (a static text dump) and above
  the empty 2D/3D states, where none of them do anything. They are also rendered
  *before any run*, at "cycle 0" with a live-looking slider, directly above the words
  "Run a program first" — three contradictory signals in one 100 px band.
- **The automaton pane grows a second control row** (`abstract numbers`, `hide
  self-loops`) that pushes the diagram down, and adds a second `?` chip. Only this pane
  has options, and they appear and vanish as you switch tabs.
- **The timeline does not use the pane.** It renders as a small block anchored low and
  right in a mostly empty area; on `lights.lps` during a live session it shrank to a
  postage stamp in the bottom third. The `composites` lane is drawn and labelled even
  when it is always empty. Event labels overlap each other on `goat_declarative`.
- **The 3D pane repeats the hint.** It carries its own *"drag: rotate · shift-drag: pan
  · scroll: zoom · right-click: why?"* while the header simultaneously says "right-click
  anything to ask why it happened".
- **The scene toolbars are cryptic and hidden.** The 2D/3D pane offers `+ − ⤢ PNG Rec ⇔`
  plus a chip naming a fluent (`lamp`, `loc`, `on`). `Rec` and `⇔` are unexplained, and
  `+ − ⤢` only appear on hover, so the zoom controls are undiscoverable if you never
  hover.
- **Tab names.** `timeline`, `state changes`, `state transitions`, `2D`, `3D`,
  `internal syntax` — mixed case, and the two adjacent `state …` names are near-identical
  words for a table of diffs and a state-machine diagram. Consider `Timeline`, `Changes`,
  `Automaton`, `2D`, `3D`, `Internal`.

## Running, and not running

- **`Run` on a program that does not compile appears to do nothing.** With a broken
  buffer, pressing `Run` leaves the status at the analyser's *"1 error, 1 warning"* — the
  same text as before the click — and the viewport keeps showing the *previous* program's
  results in full (I was looking at `blocks3d`'s timeline while the editor held three
  lines of nonsense). Nothing says the run was refused, and nothing marks the picture as
  stale.
- **Panes are never invalidated when the buffer changes.** Same root cause as the point
  above and as flow ③ in the animate sequence: the viewport should either follow the
  editor or say plainly that it is showing an older run.
- **The empty `maxTime` box** sits next to `Run` while the program itself says
  `maxTime(10)`. It is not clear whether empty means "use the program's", and it does not
  show the effective value.
- **Two identical bullets in the file tab mean different things.** `blocks3d •` is
  "this file has a run you can look at" (`ft-ran`); `blocks3d • •` adds the unsaved-changes
  dot. Same glyph, same size, adjacent. I misread the run dot as a dirty marker on first
  sight; so will everyone. Use different marks.

## The assistant dock

- **It is expanded by default and eats a third of the editor column** — the editor is cut
  off around line 32 of every example at 1500×940. The assistant and live docks together
  take ~300 px of vertical space that the program is not getting.
- **Its input scrolls out of reach.** See flow ② above: 123 px of viewport for 275 px of
  reply.
- ~~**The model picker is a bare list** — eight entries in provider order with no
  indication which is the sensible default.~~ **Wrong, and the mistake is instructive:**
  the picker already groups the curated models first, under the heading "known to work
  with this assistant". I read the list through `option.allTextContents()`, which
  flattens `<optgroup>` away, and reported the flattening as the UI. Nothing to fix.
- **A job that fails leaves the UI spinning forever.** A malformed request produced
  `Thread running "run_job(…)" died due to failure` in the server log while
  `assistant_status` kept returning `"status":"running"` with an empty `output` — polled
  past 150 s. `run_job/2` catches exceptions but not failure, so a failed goal never sets
  `status: error`. The browser would show *thinking…* until the tab is closed. Worth a
  `( … -> true ; set error )` regardless of how the request got malformed.

## The example browser

- Thirteen collapsible groups, all collapsed, labelled with counts (`CLOUT workshop (73)`,
  `forTesting (63)`, `PDDL (18)`, `Kowalski book (12)`) — repository-internal names in a
  dialog aimed at someone who has never seen the repository. `corpus`, `forTesting` and
  `CLOUT workshop` mean nothing to a user.
- The left column shows a bare stem (`blocks`, `lights`) and the actual filename is
  buried inside the right-hand description (`lights.lps — a program you can click on`).
- There is a filter box, which is the good part. A short "start here" row of four or five
  programs above the tree would carry most first visits.

## Small things

- The `?` chips link to `/docs/UsingTheIDE#2d` (200 OK) but are a bare grey question mark
  in a header full of other grey chrome; they read as decoration.
- ~~The build date `2026-08-05` in the top-right corner is at the same weight as the run
  status next to it.~~ **Wrong**: it is already `font-size: 11px; opacity: .5` against the
  status line's full weight. It only looked equal in a screenshot.
- The `Copy` button on **internal syntax** floats unlabelled at the top right of the
  text, with no indication of what it copies.
- `Live session` shows five buttons (`Start`, `Pause`, `Resume`, `Stop`, `2D`, `3D`) with
  the disabled ones only slightly dimmer than the enabled ones, and its feed stayed empty
  while a session was running.
- On a fresh window both docks render expanded even though their markup carries
  `class="dock collapsed"`; after some navigation they come back collapsed. Whatever the
  rule is, it is not visible to the user.

---

## What is good, and should not be lost while fixing the above

- The end product of the animate flow is excellent: the goat scene, the lamps and the
  3D block tower all read at a glance and are worth the trouble it takes to reach them.
- `lights.lps` genuinely is clickable, and the *"click a lamp"* caption drawn by the
  program itself is the right idea.
- The why-modal is the best thing in the IDE: right-click a bar, get
  *"lamp(1,on) — cycle 0 … holds at cycle 0 in the initial state — and nothing has
  terminated it"*, plus the grammar of questions it accepts. It deserves to be more
  discoverable than a hint in a corner.
- `internal syntax` with provenance back to the surface line is a real debugging tool.
- The run itself is fast enough (4–14 ms for these programs) that nothing about the
  latency needs defending — which is exactly why the four-step animate flow stands out.

---

## Afterword: what the blocks picture turned out to be about

Raised separately, and the deeper of the two problems. `docs/uglyBlocks.png` shows what
*Animate in 2D* made of blocks world: seven boxes stacked down the page, each containing
one small blue square, the squares at meaningless horizontal offsets, and no tower
anywhere. Scrubbing the cycles moved the squares between the boxes without ever building
or dismantling anything.

That was not a prompting accident. The plan grammar had two shapes — containers and
gauges — and `on(Block, Support)` fits "containers" perfectly *as a sentence*: an
argument that says where a thing is. What it does not fit is the geometry, because the
places are the things: block `b` was drawn once as a container and once as a square
inside container `c`, and every block appeared twice.

The fix is a third shape, `stacks`, and one property of it is the interesting part: a
stack **cannot have a slot table**. How high a block is drawn depends on how many blocks
are under it *at that cycle*, so the position is not precomputable at all. What the layout
layer now generates is a short recursion over the state — `lps_pile_top/2` and
`lps_pile_x/2` calling `state/1` — which is exactly what `examples/blocks3d.lps` had been
writing by hand since M15. The hand-written file was the existence proof and nobody had
noticed it was one.

Three further things came out of it, and they are worth separating from the UI list:

- **The reading is promoted, not demanded.** A plan that makes containers of things it
  also puts *in* containers is turned into a stack automatically, with a note saying so.
  Prompts are advice; this is the layer refusing to draw the incoherent thing. The goat's
  two river banks share no name with its four animals and are left exactly as they were.
- **"Animate in 3D" was still asking the model for coordinates** — the very job §I.10.4e
  exists to take away from it, handed back with one more axis to get wrong. Both buttons
  now send the same plan and `lps_scene.pl` renders it twice: the container grid becomes a
  floor plan, things stand up out of their slab, a stack is a tower, and the ground plane,
  camera and light are computed rather than remembered.
- **3D labels floated a fixed distance above their object**, which is right for things
  standing apart on a floor and wrong for anything stacked: at a 1.8 pitch the offset of
  1.72 put each block's name on the block above it, so a seven-block tower read as
  labelled one out with an anonymous block at the bottom. A label now sits *on* an object
  big enough to carry it, which is the rule the 2D renderer already followed.

## Afterword 2: the prompt had quietly outgrown half the models

Reported straight after the above, and worth separating because the cause is not where it
looks: *Animate in 2D* on `blocks.lps` came back with **"the model provider refused the
request: This model's maximum context length is 8192 tokens. However, your messages
resulted in 12543 tokens."**

Nothing about that sentence is actionable by the person who pressed the button. They did
not choose the length of the messages — `lps_assistant.pl` did, by inlining the whole of
`docs/lps_summary.md` into every request. Measured: 30,891 characters of language
reference (≈7,700 tokens), 7,087 of icon catalogue, the program, and the command. The
single largest piece was §18's table of `display/2` shapes and properties — which the
model has had no use for since the day it stopped writing display clauses.

Three changes, and the first is the one that matters:

- **The animate buttons get the sections that help read a program** (§§1, 3, 4, 5, 8, 11),
  selected from the file by heading rather than copied into a second string that would be
  out of date within a month. A typed question still gets the whole thing. 11,000 tokens
  → 5,190 for `blocks.lps`.
- **The completion budget is scaled from the program, not fixed at 8,000.** This is a
  second way to be refused by the same limit and the shorter prompt does not fix it:
  OpenAI counts the reservation against the context window, so 5,200 tokens of prompt plus
  an 8,000-token reservation overruns an 8,192-token model by half again. The largest
  honest reply is the program handed back, so that is the scale. `blocks.lps` now asks for
  2,672, and the whole exchange fits an 8,192-token model.
- **A model's context window is read from the provider's catalogue** where there is one
  (Groq reports `context_window`; OpenAI and Anthropic do not, and are then simply
  unconstrained here). The picker marks the ones that are too small — *"allam-2-7b (groq)
  · 4k — may be too small"* — and the assistant refuses before sending, naming models on
  this server that would fit. A refusal that does arrive from the provider is rewritten
  into the same terms rather than passed through verbatim.

The general lesson is the one the pane strip taught in a different key: a limit that the
software knows about and the user does not is not an error message, it is a trap. Offering
a model that cannot do the job, and only saying so after it has been chosen and the request
has failed, is the same defect as dimming a tab that works.
