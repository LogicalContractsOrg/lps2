/* explain_test.pl — the M9 gate.

   > M9 gate: All explanation question forms covered.

   §I.10.5 names five question forms and, for the hard one, four cases that
   must be answerable plus an honest fallback. This checks each of them
   against a real program with a known trace, asserting the *verdict* rather
   than the prose: the prose is a rendering, the verdict is the claim.

   Usage:
     ./myswipl.sh -q -g "consult('tools/explain_test.pl')" -g "xt:main" -t halt
*/

:- module(xt, [ main/0 ]).

:- use_module(library(lists)).
:- use_module('../src/core/lps_ops').
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_explain').

main :-
	corpus('goat.pl_.P', Goat),
	corpus('forTesting/badlight2.pl_.P', Light),
	corpus('forTesting/prospectiveGoat2.pl_.P', Prosp),
	session(Goat, GS),
	session(Light, LS),
	session(Prosp, PS),
	unreachable_session(US),
	refusing_session(RS),
	invariant_session(IS),
	findall(r(N, V), ( check(GS, LS, PS, US, N, V) ; refused_check(RS, N, V)
			 ; invariant_check(IS, N, V) ), Rs),
	include([r(_, pass)]>>true, Rs, Passes),
	length(Passes, NP), length(Rs, N),
	format('~n=== explanation question forms: ~w/~w ===~n', [NP, N]),
	( NP =:= N -> true ; halt(1) ).

session(File, S) :-
	lps_compile(file(File), internal, [dc], P, D),
	lps_diag:diags_ok(D),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _).

corpus(Rel, File) :-
	module_property(xt, file(F)),
	file_directory_name(F, Tools), file_directory_name(Tools, Root),
	atomic_list_concat([Root, '/legacy_lps1/examples/', Rel], File).

/* Each case names the §I.10.5 form it covers and the verdict it must reach. */

check(GS, _, _, _, Name, Verdict) :-
	goat_case(Name, Question, Expected),
	verdict_of(GS, Question, Got),
	report(Name, Expected, Got, Verdict).
check(_, LS, _, _, Name, Verdict) :-
	light_case(Name, Question, Expected),
	verdict_of(LS, Question, Got),
	report(Name, Expected, Got, Verdict).
check(_, _, PS, _, Name, Verdict) :-
	prospective_case(Name, Question, Expected),
	verdict_of(PS, Question, Got),
	report(Name, Expected, Got, Verdict).
check(_, _, _, US, Name, Verdict) :-
	planning_case(Name, Question, Expected),
	verdict_of(US, Question, Got),
	report(Name, Expected, Got, Verdict).

%	why_not — case 3 of four: a prospective constraint rejected the state the
%	action would have produced. This is the goat's own puzzle rule, stated as
%	a denial about the *next* state (§0.5).
prospective_case('why not: rejected by a prospective constraint',
		 why_not(happened(transport(cabbage, south, north)), 2),
		 rejected_by_prospective_constraint).

%	why_not — case 4 of four: under planning mode, no plan within the horizon
planning_case('why not: no plan within the horizon',
	      why_not(happened(row(south, north)), 2), no_plan_found).

/* A goal no causal law can reach, so the search exhausts the horizon. Written
   inline rather than kept as a file: it exists only to make the fourth case
   reachable, and a corpus program that fails to plan would be a corpus bug.
*/
%	An observed event that an integrity constraint refuses: a call made from
%	outside (the scenario) that the state it arrives in does not allow — a
%	revert, in a contract. It did not happen, and why_not says so, rather than
%	"no rule ever created a goal for it".
refusing_session(S) :-
	Terms = [ t(maxTime(4), 1),
		  t(events([pay(_, _)]), 2),
		  t(fluents([balance(_)]), 3),
		  t(initial_state([balance(10)]), 4),
		  t(updated(happens(pay(_, A), _, _), balance(B), B-B1, [B1 is B - A]), 5),
		  t(d_pre([happens(pay(_, A), T1, _), holds(balance(B), T1), B < A]), 6),
		  t(observe([pay(ann, 50)], 2), 7),
		  t(observe([pay(bob, 5)], 3), 8)
		],
	lps_compile(terms(Terms), internal, [dc], P, D),
	lps_diag:diags_ok(D),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _).

refused_check(RS, Name, Verdict) :-
	member(Name-Question-Expected,
	       [ 'why not: an observation a constraint refused'-why_not(happened(pay(ann, 50)), 2)-refused_by_constraint,
		 'why: an observation that happened'-why(happened(pay(bob, 5)), 3)-happened ]),
	verdict_of(RS, Question, Got),
	report(Name, Expected, Got, Verdict).

%	An invariant — a constraint about the next state alone, naming no action —
%	puts off the action that would break it. The answer names the invariant,
%	not "no applicable rule" (it did before 29 September 2026: the case above
%	looked only for constraints that name the action).
invariant_session(S) :-
	Terms = [ t(maxTime(6), 1),
		  t(fluents([cups(_)]), 2),
		  t(actions([pour]), 3),
		  t(initial_state([cups(0)]), 4),
		  t(updated(happens(pour, _, _), cups(O), O-N, [N is O + 1]), 5),
		  t(reactive_rule([holds(cups(C), T), C < 5], [happens(pour, _, _)]), 6),
		  t(d_pre([holds(cups(C), _), C > 2]), 7)
		],
	lps_compile(terms(Terms), internal, [dc], P, D),
	lps_diag:diags_ok(D),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _).

invariant_check(IS, 'why not: put off by an invariant on the next state', Verdict) :-
	verdict_of(IS, why_not(happened(pour), 4), Got),
	report('why not: put off by an invariant on the next state',
	       rejected_by_prospective_constraint, Got, Verdict).

unreachable_session(S) :-
	Terms = [ t((:- lps_engine(planning, [horizon(3), max_concurrency(1)])), 1),
		  t(maxTime(6), 2),
		  t(actions([row(_, _)]), 3),
		  t(fluents([loc(_, _), arrived(_)]), 4),
		  t(initial_state([loc(farmer, south)]), 5),
		  t(updated(happens(row(L1, L2), _, _), loc(farmer, L1), L1-L2, []), 6),
		  t(d_pre([happens(row(A, _), T1, _), holds(not loc(farmer, A), T1)]), 7),
		  t(achieve([arrived(mars)]), 8)
		],
	lps_compile(terms(Terms), internal, [dc], P, D),
	lps_diag:diags_ok(D),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _).

%	why(happened(A), T) — the rule/goal chain
goat_case('why action happened', why(happened(row(south, north)), 2), happened).
%	…and the same question when it didn't, which must redirect rather than
%	invent a chain
goat_case('why action happened (but did not)', why(happened(row(north, south)), 2), did_not_happen).

%	why(holds(F), T) — last initiating event, or persistence
goat_case('why fluent holds', why(holds(loc(goat, north)), 3), holds).
goat_case('why fluent holds (it does not)', why(holds(loc(goat, north)), 1), does_not_hold).

%	why(stopped(F), T) — the terminating event
goat_case('why fluent stopped', why(stopped(loc(goat, south)), 4), terminated).
goat_case('why fluent stopped (it has not)', why(stopped(loc(wolf, south)), 2), still_holds).

%	why_not — case 2 of four: a denial blocked the action
goat_case('why not: blocked by a denial',
	  why_not(happened(transport(wolf, south, north)), 2), blocked_by_denial).
%	why_not — case 1 of four: no rule instance ever created the goal
goat_case('why not: no goal was ever created',
	  why_not(happened(fly(farmer)), 2), no_goal_created).
%	why_not applied to something that did happen must say so
goat_case('why not: it did happen', why_not(happened(row(south, north)), 2), happened).

/*  why_not(holds(F), T) — the counterfactual about *state*, which the
    explanation panel needs because a fluent that is not true cannot be clicked
    on. Four answers, and the first two are the ones a program written with
    `updates` gets: the goat moves everything with `updates`, so before this
    existed both `why(holds(…))` and this question fell through to "no recorded
    cause" — the record was there, and the question was being asked of the
    wrong half of it. */
goat_case('why not: a fluent that does hold',
	  why_not(holds(loc(goat, north)), 3), holds).
goat_case('why not: it held and was terminated',
	  why_not(holds(loc(farmer, north)), 7), terminated).
goat_case('why not: nothing in the program can make it true',
	  why_not(holds(nonsense(x)), 3), never_held).
%	…and the positive form on a fluent an `updates` law put there, which is
%	the case that reported "no recorded cause".
goat_case('why holds, when an updates law set it',
	  why(holds(loc(wolf, north)), 6), holds).

%	what_if — fork, replay, diff (§I.6 in anger)
light_case('what if: a different observation',
	   what_if([goto(dad, bathroom)], 2), differs).
light_case('what if: an observation that changes nothing',
	   what_if([], 2), no_difference).

verdict_of(S, Question, Verdict) :-
	catch(lps_session_explain(S, Question, explanation(_, Verdict, _)), E,
	      ( Verdict = error(E) )).

report(Name, Expected, Got, Verdict) :-
	(   Got == Expected
	->  Verdict = pass, format('~w~t~48| ~w~n', [Name, Got])
	;   Verdict = fail,
	    format('~w~t~48| expected ~w, got ~q~n', [Name, Expected, Got])
	).
