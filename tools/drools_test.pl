/* drools_test.pl — the M12d gate.
 *
 * §IV.5 says every transpiler needs its own oracle, and names the one for
 * Drools: "agreement on which rules fire in which order". The real thing is a
 * Java harness running the same scenario through a KieSession with an
 * AgendaEventListener; that needs a JVM, and this container has none, so the
 * oracle here is the next thing down — **the expected firing sequence,
 * written out by hand from the rule base's documented behaviour and checked
 * in beside it**.
 *
 * That is weaker than differential testing against Drools and it is honest
 * about being weaker: it catches a translation that fires the wrong rule, in
 * the wrong order, or on the wrong facts, and it does not catch a shared
 * misunderstanding of what Drools would do. Building the Java side is the
 * first thing to do when a JVM is available (§IV.6).
 *
 *   ./myswipl.sh -q -g "consult('tools/drools_test.pl')" -g "drools_test:main" -t halt
 */

:- module(drools_test, [main/0]).

:- use_module(library(lists)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_diag').
:- use_module('../src/syntax/lps_drools').

/* case(File, InitialFacts, ExpectedFirings, ExpectedDiagnostics).
 *
 * ExpectedFirings is the sequence of *actions* (rule consequences), one list
 * per cycle, ignoring cycles in which nothing fired.
 */
case('fire-alarm',
     [fire(kitchen), sprinkler(kitchen, off), sprinkler(office, off)],
     [[insert_alarm(yes), modify_sprinkler(kitchen, on)]],
     0).
case('fire-alarm-out',
     [alarm(yes)],
     [[retract_alarm(yes)]],
     0).
case('discount',
     [order(acme, large), customer(acme, gold)],
     [[insert_discount(acme, best)]],
     2).                     % two salience warnings
case('discount-standard',
     [order(zeta, large), customer(zeta, silver)],
     [[insert_discount(zeta, standard)]],
     2).

%	Which DRL file a case uses (several cases share one rule base, with
%	different initial working memories).
file_of(Case, File) :-
	(   sub_atom(Case, B, _, _, '-'), sub_atom(Case, 0, B, _, Base),
	    exists_drl(Base)
	->  File = Base
	;   File = Case
	).

exists_drl(Base) :-
	atomic_list_concat(['examples/drools/', Base, '.drl'], P),
	exists_file(P).

main :-
	format('~n=== M12d: Drools DRL through LPS(2) ===~n~n', []),
	findall(R, ( case(C, Facts, Expected, NDiag), run_case(C, Facts, Expected, NDiag, R) ), Rs),
	include(==(ok), Rs, Oks),
	length(Rs, N), length(Oks, NOk),
	format('~n=== ~w/~w rule bases behave as expected ===~n', [NOk, N]),
	( NOk =:= N -> true ; halt(1) ).

run_case(Case, Facts, Expected, NDiag, Result) :-
	file_of(Case, Base),
	atomic_list_concat(['examples/drools/', Base, '.drl'], File),
	drl_to_internal(File, Terms0, Diags),
	length(Diags, ND),
	append(Terms0, [t(initial_state(Facts), src(File, 1, 0, drl)),
			t(maxTime(6), src(File, 1, 0, drl))], Terms),
	lps_compile(terms(Terms), internal, [dc], Program, CDiags),
	(   diags_ok(CDiags)
	->  lps_session_new(Program, [dc], S0),
	    lps_session_run(S0, end, _, Trace),
	    findall(Sorted, ( member(stage(events, C, Items), Trace), Items \== [], C > 1,
			      msort(Items, Sorted) ), Firings0),
	    dedupe_consecutive(Firings0, Firings),
	    maplist(msort, Expected, ExpectedSorted),
	    (	Firings == ExpectedSorted, ND =:= NDiag
	    ->	Result = ok, Verdict = ok
	    ;	Result = failed,
		format(atom(Verdict), 'expected ~q + ~w diags, got ~q + ~w diags',
		       [ExpectedSorted, NDiag, Firings, ND])
	    )
	;   Result = failed, Verdict = 'does not compile'
	),
	format('~w~t~24| ~w~n', [Case, Verdict]).

%	A rule that stays satisfied fires once in LPS and once in Drools; the
%	engine re-posts the same action each cycle while its condition holds,
%	so consecutive identical cycles are one firing.
dedupe_consecutive([], []).
dedupe_consecutive([X], [X]) :- !.
dedupe_consecutive([X, X|T], Out) :- !, dedupe_consecutive([X|T], Out).
dedupe_consecutive([X|T], [X|Out]) :- dedupe_consecutive(T, Out).
