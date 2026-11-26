# LOMO duties through time

LOMO, the Legal Obligation Metadata Ontology of the European institutions,
describes the rules of a legal text: who must do what, by when. LE2 reads a
LOMO description into a Logical English *register* (LE2
`examples/migration/lomo/`), and its library `lomo.le` says, for one day,
which duties of a case are open, met or late.

This folder is the same reading through time. `lomo_calendar.le` is a
library in Logical English for LPS: a duty starts when its trigger happens to
a party, ends when the party does the action in time, and is breached when the
clock passes the due day. Each other program is one case. The LOMO
translator of LE2 (`migration/lomo/lomo_lps.pl`) wrote it from a register and
a case, and the first lines of each program say how the run must end.

| Program | The case |
|---|---|
| `probe_to_1_april_2026.le` | GDPR Article 33 and Directive 2013/34/EU: acme notifies a breach one day late; on 1 April 2026 the publication is still open |
| `probe_to_15_january_2027.le` | The same case, to 15 January 2027: the publication is breached too |
| `financial_reporting_2027.le` | Directive 2013/34/EU Article 30(1): bigco publishes in time, smallco does not |

## Try this
1. Open `probe_to_1_april_2026.le` and click **Run**.
2. Look at the last cycle: acme breached the notification (due on day 64), and acme owes the publication (due on day 366).
3. Open `probe_to_15_january_2027.le` and click **Run**. The publication is breached too.

## More
- A date of a case is a day number: LE for LPS counts days, not calendar dates. Day 0 is the day before the first date of the case (the first lines of each program give it).
- A rhythm ("every year") is not in this library yet: LE2's timeless calendar has it.
- What follows a breach is not in LOMO. Add it as one more law.
- The descriptions and the data of LOMO: (c) European Union, Creative Commons Attribution 4.0. The programs: Apache License 2.0.
