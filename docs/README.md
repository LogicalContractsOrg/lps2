# LPS2 documentation

| Folder | What | Published |
|---|---|---|
| [`user/`](user/) | the user documentation: tutorials, the IDE guide, references, overviews. [`user/nav.json`](user/nav.json) is its table of contents, from which the IDE's Help menu, the start page's Documentation list are built | yes, at `/docs/user/…` |
| [`dev/`](dev/) | the LE2↔LPS2 interface, the selection semantics, the IDE's design record, deployment, telemetry, the generated conformance reports | no |
| [`project/`](project/) | the plan of record, plans, user reviews, the demo video's script, historical documents | no |

Every document (but the generated conformance reports) says under its title
what kind of document it is, for whom, and whether it is current.

- **User:** [Learning LPS](user/tutorials/lps-tutorial.md), [LPS for Inform users](user/tutorials/inform-users.md), [using the IDE](user/guide/ide.md), [language reference](user/reference/lps.md), [Logical English for LPS](user/reference/le-for-lps.md), [glossary](user/reference/glossary.md), [Introducing LPS2](user/overview/introducing-lps2.md), [a two-page summary](user/overview/abstract.md).
- **Developer:** [the LE2↔LPS2 interface](dev/le-lps-interface.md), [selection spec](dev/semantics/selection-spec.md), [IDE design record](dev/ide-design.md), [deploy](dev/deploy.md), [telemetry](dev/telemetry.md), [conformance reports](dev/conformance/).
- **Project:** [the plan of record](project/plan-of-record.md) (its Status section is where project status lives), [plans](project/plans/), [reviews](project/reviews/), [videos](project/videos/), [historical](project/historical/).

`le-for-lps.md` and `le-lps-interface.md` are LPS2's; LE2 links to them instead of keeping copies.
`dev/conformance/*.md` are generated (`conformance/runner.pl`): do not edit them by hand.
The assistant reads `user/reference/lps.md` by path (`src/edges/lps_assistant.pl`).
`vibeCodingNotes.md` is private notes, not served and not in the image.
