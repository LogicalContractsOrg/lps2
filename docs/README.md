# LPS2 documentation

| Folder | What | Published |
|---|---|---|
| [`user/`](user/) | the user documentation: tutorials, the IDE guide, references, overviews. [`user/nav.json`](user/nav.json) is its table of contents, from which the IDE's Help menu, the start page's Documentation list are built | yes, at `/docs/user/…` |
| [`dev/`](dev/) | the LE2↔LPS2 interface, the selection semantics, the IDE's design record, the two deployments, telemetry, the generated conformance reports | no |
| [`project/`](project/) | the plan of record, plans, user reviews, the demo video's script, historical documents | no |

The viewer's shared script, `ui/static/docs-extras.js` (identical in LE2 and LPS2:
keep the copies equal), gives every document three things. **Search**:
`/docs/search?q=…` searches the documents of `nav.json`, section by section,
deterministically; a document not in `nav.json` is not searched. **Links to
the other IDE**: write them as `https://lps2.logicalcontracts.com/docs/user/…`
(from LE2) or `https://le2.logicalcontracts.com/docs/user/…` (from LPS2); the
viewer rewrites them to wherever the other IDE is (le2.DOMAIN ↔ lps2.DOMAIN; on
localhost ports 3000 ↔ 3060; `?peer=<origin>` overrides). **Diagrams**:
`mermaid` code blocks are drawn with the local `mermaid.min.js`, and their
`click` links are rewritten the same way.

Every document (but the generated conformance reports) says under its title
what kind of document it is, for whom, and whether it is current.

## How documents are written

The readers are lawyers, underwriters, policy officers, accountants and other domain
experts as much as programmers, so every document — and every piece of text
the software puts in front of a reader, such as a menu tip, an explanation of
an answer, or an assistant's reply — is written to be understood by someone
with no technical training.

- **Name the thing instead of pointing at it.** Use a pronoun only when the
  noun it stands for is the one just before it and no other noun could be
  meant. Never open a sentence with *it*, *this*, *that*, *these* or *they*
  standing for the whole sentence before: repeat the noun.
- **No computing jargon without plain words in the same sentence.** Words such
  as *parse*, *instantiate*, *serialise*, *hook*, *callback*, *back end*,
  *repository*, *endpoint* and *payload* are replaced by ordinary English, or
  explained where they first appear. Name a file, a predicate or a setting
  only where the reader has to go and look at it.
- **One idea per sentence, in the order things happen.** Prefer a subject that
  acts: *the editor checks the document*, rather than *the document is
  checked*.
- **Spell out an abbreviation the first time each document uses it.**
- **Verify any examples used in the documentation.** After you write a document, namely a tutorial, you must execute a second pass looking out for code fragments, and making sure statements in your text are coherent with what the engine's execution produces.
- The names of the ideas these systems teach — a fluent, an event, a template,
  a scenario, a reactive rule — are part of the language being taught. Use
  them freely, and define each one at first use or in the glossary.

### Simplified Technical English

Write each user document in ASD-STE100 Simplified Technical English (STE).
STE is a controlled form of English for technical documents (refer to
<https://en.wikipedia.org/wiki/Simplified_Technical_English>). The model is
LE2's tutorial `docs/user/tutorials/intro-to-le/intro-to-le.md`. Obey these
rules, together with the rules above:

- **Short sentences.** Write a maximum of 20 words in a procedure, and a
  maximum of 25 words in a description. Split a long sentence; do not remove
  its content.
- **Short paragraphs.** Write a maximum of six sentences in a paragraph. Give
  each paragraph one topic.
- **Procedures as numbered steps.** Write "Do these steps:" and then a
  numbered list. Write one instruction in each step, with the command form of
  the verb ("Select…", "Click…", "Run…"). Write the result of the steps in a
  separate sentence after the list.
- **Active voice and simple tenses.** Use the present, the simple past and the
  simple future. Do not use an "-ing" form where a simple form is possible.
- **One word for one meaning.** Use the same word each time. Write "Refer to"
  for a cross-reference, "Put the mouse pointer on" for a hover, "Select" for a
  menu item or a list, and "Click" for a button.
- **Approved words.** When possible, use the words of the STE dictionary: *use*
  (not *utilise*), *make sure* (not *ensure*), *can* (not *is able to*),
  *show* (not *display*), *start* (not *launch*), *give* (not *provide*), *do*
  (not *perform*), *tell* (not *inform*), *thus* (not *therefore*), *about*
  (not *regarding*), *before* (not *prior to*).
- **No contractions, idioms, jokes or phrasal verbs** (*find out* → *find*).
  Keep the articles (*the*, *a*) that English needs.
- **Notes and warnings** come before the step that they apply to.
- **Words outside the STE dictionary** are permitted in three groups: the names
  in the user interface (menus, buttons, windows, settings), always in
  **bold** and spelled as the software spells them; the names of the ideas of
  the languages (template, scenario, query, fluent, event, reactive rule);
  and other technical names (Prolog, s(CASP), JSON). Define each one at first
  use.
- **Keep what other files depend on.** Do not change program text (code
  blocks and inline code), screenshots, link targets, quoted text from other
  sources, or a heading that other documents link to.

## The documents

- **User:** [Learning LPS](user/tutorials/lps-tutorial.md), [how a program runs](user/tutorials/how-lps-runs.md), [LPS for Inform users](user/tutorials/inform-users.md), [using the IDE](user/guide/ide.md), [language reference](user/reference/lps.md), [Logical English for LPS](user/reference/le-for-lps.md), [glossary](user/reference/glossary.md), [Introducing LPS2](user/overview/introducing-lps2.md) and its technical companion [LPS2 in detail](user/overview/introducing-lps2-technical.md), [a two-page summary](user/overview/abstract.md); other systems: [the map](user/integrations/index.md), [PDDL](user/integrations/pddl.md), [Drools](user/integrations/drools.md), [Inform 7](user/integrations/inform-7.md), [Solidity](user/integrations/solidity.md), [Daml](user/integrations/daml.md); for agents: [LPS over MCP](user/api/mcp.md).
- **Developer:** [the LE2↔LPS2 interface](dev/le-lps-interface.md), [selection spec](dev/semantics/selection-spec.md), [IDE design record](dev/ide-design.md), [deploy](dev/deploy.md) (the container, on fly.io) and [deploy as a static site](dev/deploy-vercel.md) (the WebAssembly build: the IDE in the browser, on Vercel), [telemetry](dev/telemetry.md), [conformance reports](dev/conformance/).
- **Project:** [the plan of record](project/plan-of-record.md) (its Status section is where project status lives), [plans](project/plans/), [reviews](project/reviews/), [videos](project/videos/), [historical](project/historical/).

`le-for-lps.md` and `le-lps-interface.md` are LPS2's; LE2 links to them instead of keeping copies.
`dev/conformance/*.md` are generated (`conformance/runner.pl`): do not edit them by hand.
The assistant reads `user/reference/lps.md` by path (`src/edges/lps_assistant.pl`).
`vibeCodingNotes.md` is private notes, not served and not in the image.
