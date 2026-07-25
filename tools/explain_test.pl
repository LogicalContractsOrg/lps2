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
	findall(r(N, V), ( check(GS, LS, PS, US, N, V) ), Rs),
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
