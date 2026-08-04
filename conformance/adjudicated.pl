/* adjudicated.pl — corpus entries whose golden trace cannot be met, with the
   reason written down.

   §I.1.5: "every bucket-C test either passes or has a written, reviewed
   justification". This is that register. An entry here is *not* a pass; it is
   a failure whose cause has been traced to the corpus rather than to the
   engine, and each one names the evidence.

   Keeping them separate from the regenerated goldens (conformance/regenerated.pl)
   is deliberate. A regenerated golden says "the 2021 trace is unreproducible by
   construction, here is a new one". An adjudication says "this trace is wrong
   and we are not pretending otherwise".
*/

:- module(adjudicated, [ adjudicated/3 ]).

%!	adjudicated(?Slug, -Class, -Reason) is nondet.
adjudicated(Slug, stale_golden_2019, Reason) :-
	adjudicated(Slug, stale_golden_2019),
	Reason = 'Recorded 2019-04-03 on SWI 8.1.1, before upstream began \c
		  recording real_date_begin/1 and real_date_end/1 as composite \c
		  events; the 2021 goldens in examples/ contain them and these do \c
		  not. The legacy engine fails these goldens today with exactly the \c
		  diagnoses LPS2 produces, so the divergence is the corpus, not \c
		  the engine. Use --engine cross to compare the two engines directly.'.

adjudicated('forTesting_prospectiveGoat.pl', stale_golden,
	    'Generated in 2017 on SWI 7.5.8 from a differently-named source \c
	     (prospectiveGoat.lps_.P) and containing no `composites` records at \c
	     all — a stage the engine has emitted ever since. LPS2 produces the \c
	     composites, so the extra records are the correct behaviour and the \c
	     golden is out of date. Left failing deliberately, as the user \c
	     instructed: the golden is not regenerated \c
	     here. §I.7 does not need it — §I.7.7 makes the declarative version a \c
	     *new* example (examples/goat_declarative.pl) precisely so that the \c
	     existing goat programs keep their traces.').

adjudicated('CLOUT_workshop_life.pl', stale_golden,
	    'The golden was recorded in 2017 (lps_test_options([]), SWI 7.3.33) and \c
	     covers ten cycles, but the current program declares maxTime(8). No \c
	     engine honouring that declaration can produce cycles 9 and 10, the \c
	     legacy engine included; upstream scores it "ok" only because its \c
	     comparison is driven by the cycles the run actually produced. Cycles \c
	     0-8 match exactly.').

adjudicated('forTesting_realTimeObservations.pl', stale_golden,
	    'Recorded 2017-12-11 on SWI 7.5.8, from a different repository \c
	     (logicalcontracts/), and it covers 2286 cycles. The program declares \c
	     maxRealTime(5) with simulatedRealTimePerCycle(28800), so simulated \c
	     time passes the five-second bound during the first cycle and the run \c
	     ends there. LPS2 and the legacy engine produce identical traces for \c
	     it today (--engine cross passes), so the golden predates the \c
	     declaration rather than the engines disagreeing.').

/* The six extended entries, whose goldens sit in utils/moreTestResults because
   upstream moved them "to avoid lengthy test suite runs" (its README) — and
   were then never regenerated.

   They were recorded on 2019-04-03 (SWI 8.1.1). Between then and the 2021
   goldens in examples/, upstream began recording `real_date_begin/1` and
   `real_date_end/1` as composite events: the 2021
   loanAgreementPostConditionsRT golden contains 732 of them, the 2019
   extended ones none.

   The evidence that this is the corpus and not the engine: running the
   *legacy* engine against these goldens today produces exactly the diagnoses
   LPS2 produces —

     CLOUT_workshop_loanAgreementPostConditionsRTbaseBorrowerCures.pl
       count(composites,5,actual(3),expected(1))
       count(composites,9,actual(4),expected(1))

   — the same counts, the same cycles, from both engines. `--engine cross`
   compares the two engines' traces with each other and is the check that
   actually means something here.
*/
adjudicated(Slug, stale_golden_2019) :-
	member(Slug, [ 'CLOUT_workshop_loanAgreementPostConditionsRTbaseBorrowerCures.pl',
		       'CLOUT_workshop_loanAgreementPostConditionsRTbaseBorrowerCuresRep.pl',
		       'CLOUT_workshop_loanAgreementPostConditionsRTbaseBorrowerDefaults.pl',
		       'CLOUT_workshop_loanAgreementPostConditionsRTbaseNoComplications.pl',
		       'CLOUT_workshop_loanAgreementPostConditionsRTbasePaysEarlyTricky.pl',
		       'CLOUT_workshop_loanAgreementPostConditionsRTbasePaysLate.pl'
		     ]).
