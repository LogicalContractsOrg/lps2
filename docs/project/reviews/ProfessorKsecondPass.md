# A second pass, 2026-08-20

*Kind: user review · Status: addressed*

Two comments, received after reading the documents and using the editor. They
are quoted in full, because both are about the whole thing rather than about a
feature.

> I have not found the documentation easy to read. It seems to contain lots of
> technical jargon and maybe colloquialisms that I am not familiar with.

> I have also found the user interface cluttered and confusing. There seem to be
> two control panels, one on the bottom left and the other on the top right. It's
> not obvious where to start, and what to use when. There are also lots of things
> showing that do not have an obvious interpretation or relevance.

---

## What was wrong with the interface

Both control panels were real, and the second one was worse than it looked.

The top bar held `maxTime`, Run, Step and the result of the last run. The bottom
left held two panels, the assistant and the live session. **A closed panel still
showed its whole toolbar** — collapsing hid only the body — so at rest the corner
of the screen furthest from the Run button carried twelve controls, nine of them
greyed out, none of which a first-time reader needs.

The things "showing without an obvious interpretation or relevance" could be
listed exactly:

- a model menu reading "no models", beside two *Animate* buttons that could not
  work, beside the words "no API key" — four controls conveying one fact;
- the assistant also wrote "no LLM key configured" into the top bar's status
  line, where it displaced the result of the run and had nothing to do with the
  program;
- Start, Pause, Resume, Stop, Pop out 2D, Pop out 3D, a checkbox and Save log,
  all greyed out, for a session that did not exist;
- an event menu reading "no events" and a box captioned "this program declares
  no events" — for a program that declares none;
- a bare date, `2026-08-20`, in the top right corner.

## What was done

**One control panel.** Everything that acts on the program is now in the top bar:
the menus, then `maxTime`, Run and Step, then the result of the last run, then
two buttons, *Assistant* and *Live*, that open the two panels. A lit button means
its panel is open. **A closed panel takes up no space and shows no controls at
all.** The editor gets the whole of the left column until you ask for something
else.

**An obvious place to start.** The right-hand side, before anything has been run,
is the largest empty area on the screen and the first thing a new reader looks
at. It used to say "Run a program first." — true, and unhelpful, since it named
neither a program nor the way to get one. It now gives three numbered steps, each
carrying the control that performs it: open an example, run it, read what
happened.

**Nothing is shown that cannot act.** The live panel, with no session, is a rate
and a Start button. The rest appears when there is a session for it to act on,
and the pop-out buttons appear only for a program that has something to draw. The
event-sending rows are not shown at all for a program that declares no events.
With no API key the assistant shows one sentence and the button that fixes it.
The build date now reads "build 2026-08-20".

**Two things that were quietly lying.** Starting a live session left the panes
showing whatever they had shown before, so a program with no finished run sat
saying "nothing has been run yet" while the header beside it said LIVE and the
cycle counter climbed. And hiding a panel with `display: none` silently moved
every row of the left-hand column up by one, because a hidden item is taken out
of a CSS grid altogether. Both are fixed.

## What was done to the documents

Six documents were rewritten from beginning to end, and a seventh was added.

- `README.md`
- `docs/user/overview/abstract.md`
- `docs/user/tutorials/lps-tutorial.md`
- `docs/user/guide/ide.md`
- `docs/user/reference/lps.md`
- `docs/user/overview/introducing-lps2.md`
- `docs/user/reference/glossary.md` — new

The rewrite had one rule: **a term of art is either defined where it is first
used or replaced by ordinary English.** What went was software-project jargon
that had no business in a document about LPS — "golden trace", "clean-room",
"bucket A", "adjudicated", "conformance gate", "provenance", "surface syntax",
"load-bearing", "shovel-ready", "proof of concept", "on paper", "in-loco", "the
modal", "sugar over" — together with the allusive headings and the anecdotes that
carried an argument instead of stating it.

The vocabulary of LPS itself was kept, because it is the reader's own: fluent,
event, action, causal law, reactive rule, integrity constraint, composite event,
intensional fluent.

`docs/user/reference/glossary.md` defines every term in one place, grouped by subject, with an
alphabetical index. It is linked from every document, from the Help menu and from
the start page.

Everything that was a fact in the old documents is still a fact in the new ones:
the same numbers, the same tables, the same code, the same pictures. Two things
that had gone out of date were corrected on the way — *Animate in 3D* has used
the same plan as *Animate in 2D* since 2026-08-05, and the description of the
editor's layout is now the layout described above.

Every picture in `docs/user/images/` was regenerated from the running system.

## What was deliberately not touched

- `docs/dev/le-lps-interface.md` and `docs/user/reference/le-for-lps.md` are kept identical in
  this repository and in `/LogicalEnglish2`. Rewriting either means changing the
  other repository in the same commit, which is the user's call and not mine.
- `docs/project/plan-of-record.md` is the plan of record and the one place the project's
  status lives. Its Status section records this pass; the plan itself is a
  working document rather than something written to be read cover to cover.
- `docs/dev/ide-design.md` says at the top that it has been superseded as a user guide and
  is kept for the record.
- `docs/dev/conformance/conformance_lps2.md` and `docs/dev/conformance/conformance_report.md` are generated.
- `docs/project/reviews/ProfessorKsystemImpressions.md` and `docs/project/reviews/AnotherUserImpressions.md` are
  records of what was asked for, and are left as written.
