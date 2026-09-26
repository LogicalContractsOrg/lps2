/* pddl_test.pl — the M12a gate.
 *
 * §IV.5: "Do not start a transpiler before its oracle is specified." For PDDL
 * the oracle is plan validation, and this runs it over every domain/problem
 * pair in examples/planning/:
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
 *   ./myswipl.sh -q -g "consult('tools/pddl_test.pl')" -g "pddl_test:quick" -t halt
 *
 * `quick` leaves out logistics-p1, which does not finish (see below). Both
 * first run the translation checks: the constructs beyond STRIPS (typing,
 * `or`, quantifiers, `when`, `=`, negative and disjunctive goals) are
 * translated rather than dropped, numeric fluents are refused out loud, and
 * the oracle itself refuses plans that break a type or a disjunction.
 */

:- module(pddl_test, [main/0, quick/0]).

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
%  Lights: typing, `or`, `exists`, `forall`, `imply`, `=`, conditional
%  universal effects; a negative goal, and a disjunctive goal with a
%  quantifier (an intensional `goal_reached`).
problem('lights-domain',    'lights-p1',    10, 6).
problem('lights-domain',    'lights-p2',    8,  3).
%  Last, and slowest by far: this one does not finish inside any budget worth
%  waiting for, and saying so is the point of leaving it here (§12 of
%  docs/user/overview/introducing-lps2-technical.md).
problem('logistics-domain', 'logistics-p1', 30, unknown).

main :- run(all).

quick :- run(quick).

run(Which) :-
	format('~n=== M12a: PDDL through LPS2 ===~n~n', []),
	findall(R, ( check(Name, Goal), run_check(Name, Goal, R) ), CRs),
	include(==(ok), CRs, COks),
	length(CRs, CN), length(COks, CNOk),
	format('=== ~w/~w translation checks ===~n~n', [CNOk, CN]),
	format('~w~t~22| ~w~t~38| ~w~t~46| ~w~t~54| ~w~n',
	       ['domain', 'problem', 'steps', 'opt', 'validation']),
	findall(R, ( problem(D, P, H, Opt),
		     ( Which == quick -> P \== 'logistics-p1' ; true ),
		     run_one(D, P, H, Opt, R) ), Rs),
	include(==(ok), Rs, Oks),
	length(Rs, N), length(Oks, NOk),
	format('~n=== ~w/~w plans validated ===~n', [NOk, N]),
	( NOk =:= N, CNOk =:= CN -> true ; halt(1) ).

run_check(Name, Goal, R) :-
	(   catch(Goal, E, ( print_message(error, E), fail ))
	->  R = ok, format('  ok    ~w~n', [Name])
	;   R = failed, format('  FAIL  ~w~n', [Name])
	).

		 /*******************************
		 *     translation checks	*
		 *******************************/

planning(F, Path) :- atomic_list_concat(['examples/planning/', F, '.pddl'], Path).

terms_of(D, P, Terms, Diags) :-
	planning(D, DF), planning(P, PF),
	pddl_to_internal(DF, PF, Ts, Diags),
	findall(T, member(t(T, _), Ts), Terms).

compiles(Terms0) :-
	findall(t(T, src(x, 1, 0, pddl)), member(T, Terms0), Ts),
	append(Ts, [t((:- lps_engine(planning, [search(auto), horizon(4), max_concurrency(1)])), src(x, 1, 0, pddl)),
		    t(maxTime(6), src(x, 1, 0, pddl))], Terms),
	lps_compile(terms(Terms), internal, [dc], _, Diags),
	diags_ok(Diags).

%	A scratch PDDL pair, for the constructs no example should carry.
scratch_pair(Name, Domain, Problem, DF, PF) :-
	make_directory_path('build/pddl_test'),
	atomic_list_concat(['build/pddl_test/', Name, '-domain.pddl'], DF),
	atomic_list_concat(['build/pddl_test/', Name, '-problem.pddl'], PF),
	setup_call_cleanup(open(DF, write, S1), write(S1, Domain), close(S1)),
	setup_call_cleanup(open(PF, write, S2), write(S2, Problem), close(S2)).

diag_mentions(Diags, Text) :-
	member(diag(warning, pddl_unsupported, _, M, _), Diags),
	sub_atom(M, _, _, _, Text), !.

check('typed parameters become type denials', (
	terms_of('lights-domain', 'lights-p1', Ts, _),
	memberchk(d_pre([happens(go(A, _), _, _), not(of_type(X, room))]), Ts), A == X,
	memberchk(of_type(hall, room), Ts),        % a constant of the domain
	lps_pddl:object_types(room, [room-place, lamp-thing], OTs),
	OTs == [object, place, room] )).           % an object has its type's supertypes too
check('an untyped or all-one-type domain gets no type facts', (
	terms_of('blocks-domain', 'blocks-p1', Ts, _),
	\+ ( member(T, Ts), sub_term(S, T), compound(S), functor(S, of_type, 2) ) )).
check('or in a precondition is one denial over both negations', (
	terms_of('lights-domain', 'lights-p1', Ts, _),
	member(d_pre([happens(go(A, B), _, _)|Cs]), Ts),
	Cs == [not(door(A, B)), not(door(B, A))] )).
check('= in a precondition compares the parameters', (
	terms_of('lights-domain', 'lights-p1', Ts, _),
	member(d_pre([happens(go(A, B), _, _), C]), Ts), C == (A == B) )).
check('exists in a precondition is a negation over a generated variable', (
	terms_of('lights-domain', 'lights-p1', Ts, _),
	member(d_pre([happens(flip(S, _), T1, _), holds(not([of_type(L, lamp), wired(S1, L1)]), T)]), Ts),
	S1 == S, L1 == L, T == T1 )).
check('forall + when is a conditional causal law per lamp', (
	terms_of('lights-domain', 'lights-p1', Ts, _),
	member(initiated(happens(flip(S, _), _, _), on(L), Cs), Ts),
	Cs = [of_type(L1, lamp), wired(S1, L2), not(broken(L3))],
	L1 == L, L2 == L, L3 == L, S1 == S )).
check('forall + imply in a precondition', (
	terms_of('lights-domain', 'lights-p1', Ts, _),
	member(d_pre([happens('tidy-up'(R), T1, _), of_type(L, lamp), in(L1, R1), holds(on(L2), T), broken(L3)]), Ts),
	R1 == R, L1 == L, L2 == L, L3 == L, T == T1 )).
check('a negative goal literal is not(F) in achieve, and compiles', (
	terms_of('lights-domain', 'lights-p1', Ts, _),
	memberchk(achieve(G), Ts), memberchk(not(on('strip-light')), G),
	compiles(Ts) )).
check('a disjunctive goal is an intensional goal_reached, and compiles', (
	terms_of('lights-domain', 'lights-p2', Ts, Ds),
	memberchk(achieve([goal_reached]), Ts),
	findall(B, member(l_int(holds(goal_reached, _), B), Ts), Bs), length(Bs, 2),
	Ds == [],
	compiles(Ts) )).
check('numeric fluents are refused out loud, each construct once', (
	scratch_pair(fuel,
"(define (domain fuel) (:requirements :fluents)
  (:predicates (at ?x))
  (:functions (fuel) (total-cost))
  (:action hop :parameters (?a ?b)
    :precondition (and (at ?a) (> (fuel) 0))
    :effect (and (not (at ?a)) (at ?b) (decrease (fuel) 1) (increase (total-cost) 1))))",
"(define (problem fuel-1) (:domain fuel) (:objects a b)
  (:init (at a) (= (fuel) 3) (= (total-cost) 0))
  (:goal (at b)) (:metric minimize (total-cost)))", DF, PF),
	pddl_to_internal(DF, PF, Ts0, Ds),
	diag_mentions(Ds, ':functions'),
	diag_mentions(Ds, ':metric'),
	diag_mentions(Ds, '(> (fuel) 0)'),
	diag_mentions(Ds, '(decrease (fuel) 1)'),
	diag_mentions(Ds, '(increase (total-cost) 1)'),
	diag_mentions(Ds, '(= (fuel) 3)'),
	findall(T, member(t(T, _), Ts0), Ts),
	\+ ( member(T, Ts), sub_term(S, T), compound(S), functor(S, F, _), memberchk(F, [increase, decrease, >, fuel]) ),
	compiles(Ts) )).
check('a goal that is only a negation still gives an achieve', (
	scratch_pair(neg,
"(define (domain neg) (:predicates (lit ?x))
  (:action blow :parameters (?x) :precondition (lit ?x) :effect (not (lit ?x))))",
"(define (problem neg-1) (:domain neg) (:objects c) (:init (lit c)) (:goal (not (lit c))))", DF, PF),
	pddl_to_internal(DF, PF, Ts0, _),
	findall(T, member(t(T, _), Ts0), Ts),
	memberchk(achieve([not(lit(c))]), Ts),
	compiles(Ts),
	plan_for_problem(DF, PF, 3, Plan), Plan == [[blow(c)]] )).
check('an action with no precondition is not forbidden', (
	scratch_pair(free,
"(define (domain free) (:predicates (lit ?x))
  (:action light :parameters (?x) :effect (lit ?x)))",
"(define (problem free-1) (:domain free) (:objects c) (:init) (:goal (lit c)))", DF, PF),
	pddl_to_internal(DF, PF, Ts0, _),
	findall(C, member(t(d_pre([happens(_, _, _)|C]), _), Ts0), Cs),
	Cs = [[not(of_type(_, object))]],          % only the generator of its parameter
	plan_for_problem(DF, PF, 3, Plan), Plan == [[light(c)]] )).
check('the oracle refuses a step whose argument has the wrong type', (
	planning('lights-domain', DF), planning('lights-p2', PF),
	pddl_plan_valid(DF, PF, [[go(hall, 'wall-switch')]], V1), V1 \== valid,
	pddl_plan_valid(DF, PF, [[go(hall, kitchen)]], V2), V2 == goal_not_reached )).
check('the oracle refuses a step whose disjunction is false', (
	planning('lights-domain', DF), planning('lights-p1', PF),
	pddl_plan_valid(DF, PF, [[go(hall, kitchen)], [go(kitchen, study)]], V), V \== valid,
	sub_atom(V, 0, _, _, 'step 2') )).

run_one(D, P, H, Opt, Result) :-
	atomic_list_concat(['examples/planning/', D, '.pddl'], DomainFile),
	atomic_list_concat(['examples/planning/', P, '.pddl'], ProblemFile),
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
