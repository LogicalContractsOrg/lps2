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
:- use_module(library(terms), [variant/2]).
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
     [fire(kitchen), sprinkler(kitchen, false), sprinkler(office, false)],
     [[alarm_goes_on, sprinkler_turns_on(kitchen)]],
     0).
case('fire-alarm-out',
     [alarm(yes)],
     [[alarm_goes_off]],
     0).
case('discount',
     [order(acme, large), customer(acme, gold)],
     [[discount_starts(acme, best)]],
     2).                     % two salience warnings
case('discount-standard',
     [order(zeta, large), customer(zeta, silver)],
     [[discount_starts(zeta, standard)]],
     2).
%  A state machine: three rules that hand the light on round the cycle. The
%  same shape LPS is for, which is why it is here — and `modify` lands on
%  `updated/4`, the same term `updates … to … in …` produces.
%  It goes round for as long as the run lasts, which is the point of a state
%  machine: six cycles of maxTime(6) give five transitions. `modify` changes
%  the fact the rule matched — the light called gate — so each action names
%  it (it used to carry a fresh variable: the modify built its own copy of
%  the pattern instead of using the matched one).
case('traffic-light', [light(gate, green), tick(1)], Firings, 0) :-
	Firings = [[light_colour_becomes(amber)], [light_colour_becomes(red)],
		   [light_colour_becomes(green)], [light_colour_becomes(amber)],
		   [light_colour_becomes(red)]].
%  `not` over a pattern, in both languages, and the reason "no policy yet" needs
%  no flag.
case('insurance',
     [driver(ann, young, clean), driver(bob, mature, clean)],
     [[policy_starts(bob, low), policy_starts(ann, high)]],
     0).
%  A claim demotes an existing low band. Two cycles: the classification is
%  already there, so only the third rule can fire.
case('insurance-claim',
     [driver(cid, mature, claimed), policy(cid, low)],
     [[policy_band_becomes(cid, standard)]],
     0).
%  `retract` of a *pattern variable*, which is the case the generic path got
%  wrong: it made an action named after the variable that terminated nothing,
%  so the rule fired for ever and the fact stayed.
case('shipping',
     [order(o1, placed), stock(widget, available)],
     [[shipment_starts(o1), order_state_becomes(o1, shipped), stock_level_becomes(low)],
      [order_ends(o1, shipped)]],
     0).

%	Which DRL file a case uses (several cases share one rule base, with
%	different initial working memories).
file_of(Case, File) :-
	(   sub_atom(Case, B, _, _, '-'), sub_atom(Case, 0, B, _, Base),
	    exists_drl(Base)
	->  File = Base
	;   File = Case
	).

exists_drl(Base) :-
	atomic_list_concat(['examples/migration/drools/drl/', Base, '.drl'], P),
	exists_file(P).

main :-
	format('~n=== M12d: Drools DRL through LPS2 ===~n~n', []),
	findall(R, ( case(C, Facts, Expected, NDiag), run_case(C, Facts, Expected, NDiag, R) ), Rs),
	include(==(ok), Rs, Oks),
	length(Rs, N), length(Oks, NOk),
	format('~n=== ~w/~w rule bases behave as expected ===~n', [NOk, N]),
	( NOk =:= N -> true ; halt(1) ).

run_case(Case, Facts0, Expected, NDiag, Result) :-
	file_of(Case, Base),
	atomic_list_concat(['examples/migration/drools/drl/', Base, '.drl'], File),
	%  The facts are Drools facts; the program is the world reading of the
	%  rule base (a boolean field a state of its own, a field every fact
	%  gives one value left out), so they are read the same way. Its
	%  diagnostics are counted without the informational ones.
	drl_reading(File, [facts(Facts0)], reading(Terms0, Diags0, World)),
	drl_world_facts(World, Facts0, Facts),
	exclude([diag(info, _, _, _, _)]>>true, Diags0, Diags),
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
	    %  Not `==`: an action argument the rule leaves unbound reaches the
	    %  trace as a fresh variable — and sometimes as a '$VAR' term, because
	    %  the internal-syntax reader names its variables. Numbering both
	    %  sides makes an expectation written with `_` right rather than
	    %  nearly right, and does not weaken the comparison: two terms that
	    %  number to the same thing differ only in variable identity.
	    (	same_shape(Firings, ExpectedSorted), ND =:= NDiag
	    ->	Result = ok, Verdict = ok
	    ;	Result = failed,
		format(atom(Verdict), 'expected ~q + ~w diags, got ~q + ~w diags',
		       [ExpectedSorted, NDiag, Firings, ND])
	    )
	;   Result = failed, Verdict = 'does not compile'
	),
	format('~w~t~24| ~w~n', [Case, Verdict]).

same_shape(A, B) :-
	\+ \+ ( copy_term(A-B, A2-B2),
		numbervars(A2, 0, _), numbervars(B2, 0, _),
		A2 == B2 ).

%	A rule that stays satisfied fires once in LPS and once in Drools; the
%	engine re-posts the same action each cycle while its condition holds,
%	so consecutive identical cycles are one firing.
dedupe_consecutive([], []).
dedupe_consecutive([X], [X]) :- !.
dedupe_consecutive([X, X|T], Out) :- !, dedupe_consecutive([X|T], Out).
dedupe_consecutive([X|T], [X|Out]) :- dedupe_consecutive(T, Out).
