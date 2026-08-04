/* pddl_test.pl — the M12a gate.
 *
 * §IV.5: "Do not start a transpiler before its oracle is specified." For PDDL
 * the oracle is plan validation, and this runs it over every domain/problem
 * pair in examples/pddl/:
 *
 *   PDDL → internal syntax → the LPS planner → a plan → an independent
 *   simulator that reads the *PDDL* and says whether the plan is legal and
 *   reaches the goal.
 *
 * The two halves share no code: lps_pddl:pddl_plan_valid/4 never looks at the
 * translated LPS terms, so a bug in the translation cannot hide in the check.
 * What it does not check is plan *quality* — for that the column marked
 * `opt` carries the optimal length where it is known, and a longer plan is
 * reported rather than failed, because it is a planner finding (§I.7.4) and
 * not a transpiler one.
 *
 *   ./myswipl.sh -q -g "consult('tools/pddl_test.pl')" -g "pddl_test:main" -t halt
 */

:- module(pddl_test, [main/0]).

:- use_module(library(lists)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_diag').
:- use_module('../src/syntax/lps_pddl').

%!	problem(?Domain, ?Problem, ?Horizon, ?Optimal) is nondet.
%
%	Optimal is the shortest known plan length, or `unknown`. The blocks
%	numbers are the classic ones for those instances; gripper's optimal is
%	the textbook 4n/2 + moves.
problem('blocks-domain',    'blocks-p1',    14, 6).
problem('blocks-domain',    'blocks-p2',    14, 10).
problem('blocks-domain',    'blocks-p3',    14, 6).
problem('gripper-domain',   'gripper-p1',   24, 11).
problem('gripper-domain',   'gripper-p2',   30, unknown).
%  Hanoi's optimum is 2^n - 1, which is a number you compute rather than look
%  up — a rare case where "is this plan optimal?" has an exact answer.
problem('hanoi-domain',     'hanoi-p2',     10, 3).
problem('hanoi-domain',     'hanoi-p1',     16, 7).
%  Miconic-style boarding, including one problem that needs `down` — the
%  up-only instances never exercise it.
problem('elevator-domain',  'elevator-p1',  16, 7).
problem('elevator-domain',  'elevator-p2',  12, 4).
%  Rovers: the second needs `drop`, because one store cannot hold two samples.
%  A resource constraint expressed as a denial, which is the shape LPS likes.
problem('rover-domain',     'rover-p1',     14, 3).
problem('rover-domain',     'rover-p2',     20, 7).
%  Last, and slowest by far: this one does not finish inside any budget worth
%  waiting for, and saying so is the point of leaving it here (§18 of
%  docs/IntroducingLPS2.md).
problem('logistics-domain', 'logistics-p1', 30, unknown).

main :-
	format('~n=== M12a: PDDL through LPS2 ===~n~n', []),
	format('~w~t~22| ~w~t~38| ~w~t~46| ~w~t~54| ~w~n',
	       ['domain', 'problem', 'steps', 'opt', 'validation']),
	findall(R, ( problem(D, P, H, Opt), run_one(D, P, H, Opt, R) ), Rs),
	include(==(ok), Rs, Oks),
	length(Rs, N), length(Oks, NOk),
	format('~n=== ~w/~w plans validated ===~n', [NOk, N]),
	( NOk =:= N -> true ; halt(1) ).

run_one(D, P, H, Opt, Result) :-
	atomic_list_concat(['examples/pddl/', D, '.pddl'], DomainFile),
	atomic_list_concat(['examples/pddl/', P, '.pddl'], ProblemFile),
	(   catch(plan_for_problem(DomainFile, ProblemFile, H, Plan), E,
		  ( message_to_text(E, M), Plan = error(M) ))
	->  true
	;   Plan = none
	),
	(   Plan = error(Msg)
	->  format('~w~t~22| ~w~t~38| ~w~n', [D, P, Msg]), Result = failed
	;   Plan == none
	->  format('~w~t~22| ~w~t~38| ~w~n', [D, P, 'no plan found']), Result = failed
	;   length(Plan, Steps),
	    pddl_plan_valid(DomainFile, ProblemFile, Plan, Verdict),
	    ( Opt == unknown -> OptS = '-' ; OptS = Opt ),
	    format('~w~t~22| ~w~t~38| ~w~t~46| ~w~t~54| ~w~n', [D, P, Steps, OptS, Verdict]),
	    ( Verdict == valid -> Result = ok ; Result = failed )
	).

plan_for_problem(DomainFile, ProblemFile, H, Plan) :-
	pddl_to_internal(DomainFile, ProblemFile, Terms0, _),
	MT is H + 4,
	append(Terms0,
	       [t((:- lps_engine(planning, [search(auto), horizon(H), max_concurrency(1)])),
		  src(DomainFile, 1, 0, pddl)),
		t(maxTime(MT), src(DomainFile, 1, 0, pddl))],
	       Terms),
	lps_compile(terms(Terms), internal, [dc], Program, Diags),
	( diags_ok(Diags) -> true ; throw(compile_failed(Diags)) ),
	lps_session_new(Program, [dc], S0),
	lps_session_run(S0, end, _S, Trace),
	findall(Items, ( member(stage(events, C, Items), Trace), Items \== [], C > 1 ), Plan),
	Plan \== [].

message_to_text(E, S) :- format(string(S), '~q', [E]).
