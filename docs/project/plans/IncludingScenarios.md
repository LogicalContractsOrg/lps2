# Including scenarios from other files

*Kind: plan · Status: proposed (2026-11-18), not started*

A scenario is a named set of facts that describes one case. The system runs a scenario
to answer a query, or, in an LPS document, to make one run of the program. At present,
a document cannot get its scenarios from a different file. This plan adds that ability
to both plain Logical English (LE) and Logical English for LPS. The work is in LE2,
because LE2 reads the documents of both. LPS2 gets the result with no change of its own
other than tests and documents.

## 1. What exists now

A document can use three ways to get text that is not its own. They are easily confused,
so this section puts them side by side.

| | `includes these resources:` | `extends` | Companion `.lps` file |
|---|---|---|---|
| Where it works | Plain LE and LE for LPS | LE for LPS (it is read in plain LE, but only the LPS checks use it) | LPS2 only |
| How a document asks for it | A section before the knowledge base | `the knowledge base X extends B.` | Nothing: `foo.lps` is used with `foo.le` because of its name |
| Implemented in | LE2 `le_kbs.pl`, `fetch_resources/3` | LE2 `le_kbs.pl`, `fetch_base/4`; the checks in `le_lps.pl` | LPS2 `src/edges/lps_le.pl` |
| What comes in | Templates, rules, ontology, the resources that the file includes. For LPS, also its `initially` sentences and its settings | Templates, laws, constraints and timeless rules only (the contract) | LPS and Prolog clauses: `display/2`, `findall`, engine settings |
| What is left out | Scenarios and queries | Also `initially` sentences and settings | — |
| Special abilities | A `.pl` resource gives Prolog clauses to `prolog` goals (LE2 reasoner only; the LPS translation does not use them) | `this law replaces law L of B.`; the warnings `lps_replaces` and `lps_extends_clash` | — |

Thus `includes` copies everything except the cases. `extends` copies only the agreement,
and a document that extends it can replace a named law. No mechanism shares scenarios
or queries.

## 2. Decisions

- **A new section, not a change to `includes these resources:`.** About 260 `.le` files
  use `includes these resources:`. Many of the files that they include have their own
  test scenarios. If the present section also brought in scenarios, those scenarios would
  appear in each program that includes the file. Their names would clash, and the test
  suites would run them again.
- **`extends` stays contract-only.** A base describes an agreement, not a case. This is
  the reason in le-for-lps.md §1.1, and it does not change.

The new section:

```
the knowledge base tax includes these scenarios: cases/2025, cases/edge.
```

Its meaning: the system reads each named file completely. It keeps the scenarios, the
queries and their `expects` lines, in addition to everything that `includes these
resources:` keeps. The rules and templates of the file also come in. This permits a
scenario file to include the rules that it tests. When the main program includes the
same rules, the system reads them one time only, because the present guard against a
file read two times already does this.

Paths, the limit on depth, the restriction on local paths and the `.le` extension are
the same as for `includes these resources:` (LE2 language.md §14).

## 3. Steps

1. **Grammar and dictionaries (LE2).** Add the header `includes these scenarios:` to the
   CSV dictionaries under `i18n/`, with a column for each language, and to
   `le_grammar.pl`. The parser makes a new section, for example
   `scenario_resources(Name, Resources, Start, End)`. The editor's colours come from the
   same tables.
2. **Loading (LE2 `le_kbs.pl`).** Give `fetch_resources/3` a third kind of item,
   `scenarios(R)`, next to `include(R)` and `base(Child, R)`. Read the file in the same
   way as an include, but do not remove its scenario and query sections. Each included
   file already has its own range of character positions. Thus test reports,
   *Show definition* and the problems of a file will point into the scenario file with
   no more work.
3. **Clashes of names.** When two scenarios, or two queries, have the same name, report
   an error that gives the two locations. Put the error on the `includes these
   scenarios:` line of the document on the screen.
4. **LPS (LE2 `le_lps.pl`, LPS2 `lps_le.pl`).** `run_scenario/3` and
   `lps run --scenario NAME` must find the scenarios that come from a file. The
   proposed rule for `initially` sentences in a scenario file: they are part of the
   case, so they are kept. This is the opposite of `extends`, and the reason is the
   same: `initially` describes a case.
5. **Editor and test suites.** The lists of scenarios and queries in the editors of LE2
   and LPS2 must show the included ones. `runTests` and `runTestsFor` in LE2 must run
   them, and the status files must count them. Find out if a scenario file that is
   itself in an example tree is then run two times by the suite. If so, decide which
   copy the suite runs.
6. **Tests.** Add a small example under LE2 `examples/moreExamples/language/includes/`
   (rules file, scenario file, main program) and a plain LE unit test in
   `testing/`. Add one LPS example in LPS2 that runs a scenario from a file, with a test
   in `tools/`.
7. **Documents.** LE2 language.md §14 gets the new section. LPS2 le-for-lps.md §1.1
   gets a reference to it. Put the table of §1 above into the reference documents of
   both repositories, rewritten in Simplified Technical English, so that a reader can
   see the three mechanisms side by side.

## 4. Later, and optional

- **An explicit companion file.** Permit `includes these resources: foo.lps` as a
  clear form of the companion rule. The present rule, a file with the same name, can
  stay as the default.
- **`.pl` resources in LPS documents.** At present, an LPS document that includes a `.pl`
  resource appears to get nothing from it. Either carry the clauses into the LPS program
  or give a warning. Check this before deciding.
