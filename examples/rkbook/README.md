# Kowalski's book, in LPS

*Computational Logic and Human Thinking: How to be Artificially Intelligent*
(Kowalski, CUP 2011) is the book LPS and Logical English both descend from.
The LogicalEnglish2 repository has already done two thirds of a job on it:

- **`docs/RK_book/bookExamples.md`** — a 4,979-line survey cataloguing **226
  examples**, each transcribed and judged twice: complete or fragment, and
  *fits current LE* / *partially* / *not yet*, naming the missing construct.
- **`examples/moreExamples/rkBook/`** — **22 `.le` programs**, one per example
  that fitted, all verifying clean.

The remaining **132** are the interesting ones here, because of *why* they were
left out. `bookExamples.md`'s own list of what LE lacks reads as a description
of LPS: maintenance goals and the observe–think–decide–act cycle; event- and
situation-calculus primitives; explicit integrity constraints and prohibitions;
forward-chaining condition–action rules.

Counting the blockers each of those 132 entries names:

| | count | |
|---|---:|---|
| blocked **only** on constructs LPS has | 68 | the cycle, maintenance goals, constraints, forward chaining, the event calculus |
| blocked on things **LPS also lacks** | 27 | connection graphs and resolution machinery, decision-theoretic utilities and probabilities, biconditionals used as equivalences, full self-reference |
| mixed | 4 | need splitting |
| blocker not named mechanically | 33 | a case-by-case read |

## What is here

Twelve programs, chosen to cover the chapters whose subject *is* the agent
cycle, and to put at least one program against each construct LE could not
express. Each carries its chapter and section in a header comment.

| file | book | what it is for |
|---|---|---|
| `underground.lps` | ch. 1 | the Emergency Notice: a goal-reduction imperative, two conditionals and a prohibition, driving a cycle. The book's flagship example, and "fits LE *partially*" |
| `penalty.lps` | ch. 1 §1.5 | the penalty sentence as an *inhibitor of action* — the same English as a belief and as a constraint, so the traces can be compared |
| `fox_crow.lps` | ch. 3, §3.4 | the fox's goal, the crow's song, and the crow learning. LE has the beliefs; the story needs time |
| `louse.lps` | ch. 7 §7.5 | three condition-action rules, and a conflict resolved by a constraint where a production system used priority |
| `mars_explorer.lps` | ch. 7 §7.7–7.8 | the same shape with a model of the world, and condition-action rules with implicit goals |
| `hunger.lps` | ch. 8 §8.3 | the maintenance goal with explicit time — and the persistence axiom the book needs, which LPS does not |
| `umbrella.lps` | ch. 11 §11.2 | the half of a decision-theoretic example that survives without utilities: the constraint form |
| `trolley.lps` | ch. 12 §12.2–12.3 | the runaway trolley, and the computational case for moral constraints. Ask it `why_not(happened(push(bystander)), 2)` |
| `violations.lps` | ch. 12 §12.4 | what to do about violations: prohibition on our agent, sanction on anyone |
| `citizenship_time.lps` | ch. 6 §6.3 | the British Nationality Act with time made explicit — "was X a citizen on the fourth of July" |
| `event_calculus.lps` | ch. 13 §13.3–13.4 | the simplified calculus of events, where the LPS version is nearly a tautology and the frame axiom disappears |
| `plan_generation.lps` | ch. 13 §13.6 | the same axioms run backwards — which is `achieve` |

Run them all:

```sh
./myswipl.sh -q -g "consult('tools/rkbook_test.pl')" -g "rkbook_test:main" -t halt
```

## Coverage, honestly

**Converted (12 files, above).** Each is a faithful rendering of the example's
*logical content*; none is a transcription, because the book writes in an
informal pre-LE notation and LPS is a language.

**Folded.** Several catalogued entries are the same example at different stages
of the book's exposition — §1.2's disambiguated sentences and §1.4's forward
reasoning are `underground.lps`; §7.9 and §7.10's production-system readings are
`louse.lps` and `mars_explorer.lps`; §13.7's partially-ordered time and §13.8's
timekeeping are `event_calculus.lps`, whose cycle counter *is* the book's time.

**Excluded, with the reason.** Of the 132, the 27 blocked on things LPS also
lacks stay excluded, and saying so is the point — §I.9.6's discipline applied
to a second surface:

| what | why LPS cannot express it |
|---|---|
| connection graphs, resolution steps (ch. 3 §3.3, ch. 4, appendix) | proof-machinery diagrams, not programs. LPS has a derivation forest and shows it, but it is a *record* of a run rather than a search space to draw |
| decision-theoretic utilities and probabilities (ch. 11 §11.2–11.4) | there are no numbers on outcomes in LPS, and adding some would be a different language. The constraint half is in `umbrella.lps` |
| biconditionals as equivalences (ch. 15) | LPS clauses are conditionals; the completion is a semantics, not a construct |
| full object/meta-language mixing and self-reference (ch. 14, ch. 16) | a program can call Prolog, which is the escape hatch, but the book means something stronger |
| the figures | connection graphs, search trees and semantic networks are pictures of reasoning, and reproducing them is a drawing exercise |

**Not yet done.** The remaining entries — chapters 2, 9, 10 and 15's
abduction-heavy material, and the 33 whose blocker was not named mechanically —
are read but not converted. Abduction in particular deserves care rather than
speed: LPS has no `unknown`, and whether the right rendering is an open
predicate or an `achieve` is a judgement the book's own examples should settle.
