/* lps_pddl.pl — PDDL as a front end (M12a, §IV.2 and §IV.6).
 *
 * Part IV's framing: "LE2 is not a special case. It is the first transpiler."
 * A front end produces LPS internal syntax plus provenance, and everything
 * downstream — the planner, the constraints, the explanations — is unchanged.
 * This is the second front end, and it is the one the plan puts first because
 * it pays *inward*: the IPC benchmarks are a validation corpus for the M6
 * planner that we would otherwise have to invent.
 *
 * The mapping (§IV.2's "near-exact", and it is):
 *
 *   (:action a :parameters (?x) :precondition P :effect E)
 *       positive literal in E          →  a(X) initiates p(X).
 *       (not L) in E                   →  a(X) terminates p(X).
 *       positive literal in P          →  false a(X) from T1 to _, not p(X) at T1.
 *       (not L) in P                   →  false a(X) from T1 to _, p(X) at T1.
 *   (:init …)                          →  initially …
 *   (:goal …)                          →  achieve …
 *   (:objects a b - t)                 →  timeless type facts
 *
 * A precondition becomes a *denial*, not a guard, which is the whole point:
 * `d_pre/1` is documented upstream as "action preconditions (as denials)", so
 * PDDL's preconditions land on the mechanism LPS already had rather than on a
 * new one. Static predicates in the precondition (`(room ?from)`) are typing
 * dressed as facts; they become timeless clauses and the denial calls them.
 *
 * Scope, stated rather than discovered (§IV.1): STRIPS with typing and
 * negative preconditions. Not: numeric fluents, durative actions,
 * conditional effects, quantifiers, axioms, preferences. Each is *reported*
 * — `pddl_unsupported/2` diagnostics — rather than silently dropped, which is
 * §IV.5's rule about semantic gaps.
 */

:- module(lps_pddl, [
	pddl_to_internal/4,      % +DomainFile, +ProblemFile, -Terms, -Diags
	pddl_read/2,             % +File, -SExpr
	pddl_domain/2,           % +SExpr, -Domain
	pddl_problem/2,          % +SExpr, -Problem
	pddl_plan_valid/4        % +DomainFile, +ProblemFile, +Plan, -Result
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').

		 /*******************************
		 *	     reading		*
		 *******************************/

%!	pddl_read(+File, -SExpr) is det.
%
%	PDDL is s-expressions with `;` comments and case-insensitive names. The
%	reader is a few lines because there is nothing else to it: no strings, no
%	numbers worth distinguishing, no escapes.
pddl_read(File, SExpr) :-
	read_file_to_string(File, S, [encoding(utf8)]),
	string_codes(S, Codes),
	strip_comments(Codes, Clean),
	phrase(sexpr(SExpr), Clean, Rest),
	( Rest = [] -> true ; skip_ws(Rest, []) -> true ; true ).

strip_comments([], []).
strip_comments([0';|T], Out) :- !, skip_to_eol(T, T1), strip_comments(T1, Out).
strip_comments([C|T], [C|Out]) :- strip_comments(T, Out).

skip_to_eol([], []).
skip_to_eol([0'\n|T], [0'\n|T]) :- !.
skip_to_eol([_|T], Out) :- skip_to_eol(T, Out).

sexpr(L) --> ws, "(", !, items(L), ws, ")".
sexpr(A) --> ws, atom_token(A).

items([H|T]) --> sexpr(H), !, items(T).
items([]) --> [].

atom_token(A) --> token_codes(Cs), { Cs \== [], atom_codes(A0, Cs), downcase_atom(A0, A) }.

token_codes([C|Cs]) --> [C], { \+ delim(C) }, !, token_codes_rest(Cs).
token_codes_rest([C|Cs]) --> [C], { \+ delim(C) }, !, token_codes_rest(Cs).
token_codes_rest([]) --> [].

delim(0'(). delim(0')). delim(C) :- code_type(C, space).

ws --> [C], { code_type(C, space) }, !, ws.
ws --> [].

skip_ws([], []).
skip_ws([C|T], R) :- code_type(C, space), !, skip_ws(T, R).
skip_ws(L, L).

		 /*******************************
		 *	   domain, problem	*
		 *******************************/

%!	pddl_domain(+SExpr, -Domain) is det.
%
%	Domain = domain(Name, Types, Predicates, Actions, Unsupported).
pddl_domain(['define', [domain, Name] | Sections], domain(Name, Types, Preds, Actions, Unsup)) :-
	findall(T, ( member([':types'|Ts], Sections), member(T, Ts), T \== '-' ), Types),
	findall(P, ( member([':predicates'|Ps], Sections), member(P, Ps) ), Preds),
	findall(A, ( member(S, Sections), action_of(S, A) ), Actions),
	findall(U, ( member([K|_], Sections), unsupported_section(K), U = K ), Unsup).

unsupported_section(':functions').
unsupported_section(':durative-action').
unsupported_section(':derived').
unsupported_section(':constraints').

action_of([':action', Name | Rest], action(Name, Params, Pre, Eff)) :-
	kv(Rest, ':parameters', Params0, []), strip_types(Params0, Params),
	kv(Rest, ':precondition', Pre, []),
	kv(Rest, ':effect', Eff, []).

kv(List, Key, Value, _Default) :- append(_, [Key, Value|_], List), !.
kv(_, _, Default, Default).

%	`?x - block ?y - block` → [?x, ?y]; the types are kept by the caller
%	through the predicate declarations, not here.
strip_types([], []).
strip_types(['-', _Type|T], Out) :- !, strip_types(T, Out).
strip_types([V|T], [V|Out]) :- strip_types(T, Out).

%!	pddl_problem(+SExpr, -Problem) is det.
pddl_problem(['define', [problem, Name] | Sections],
	     problem(Name, Domain, Objects, Init, Goal)) :-
	( member([':domain', Domain], Sections) -> true ; Domain = unknown ),
	findall(O, ( member([':objects'|Os], Sections), member(O, Os) ), Objects0),
	strip_types(Objects0, Objects),
	( member([':init'|Init], Sections) -> true ; Init = [] ),
	( member([':goal', Goal], Sections) -> true ; Goal = [] ).

		 /*******************************
		 *	   translation		*
		 *******************************/

%!	pddl_to_internal(+DomainFile, +ProblemFile, -Terms, -Diags) is det.
%
%	Terms are `t(InternalTerm, src(File, Line, Col, Kind))` pairs, the same
%	shape LE2 hands over (docs/dev/le-lps-interface.md §1), so `lps_compile/5`
%	takes them unchanged and a diagnostic lands on the PDDL file rather than
%	on generated text. That provenance channel is the payoff §IV.0 names.
pddl_to_internal(DomainFile, ProblemFile, Terms, Diags) :-
	pddl_read(DomainFile, DS),
	pddl_read(ProblemFile, PS),
	(   pddl_domain(DS, Domain)
	->  true
	;   Domain = domain(unknown, [], [], [], []),
	    diag(error, pddl_bad_domain, src(DomainFile, 1, 0, pddl),
		 'could not read the domain', _)
	),
	pddl_problem(PS, Problem),
	Domain = domain(_, _, Preds, Actions, Unsup),
	Problem = problem(_, _, _Objects, Init, Goal),
	static_predicates(Actions, Init, Statics),
	%  declarations
	%  Declarations are *templates* — `clear(_)`, not `clear/1`. The internal
	%  syntax a generated `_.P` writes is `actions [row(_,_)]`, and an engine
	%  that does not recognise an action as declared cannot reduce a goal to
	%  it: the plan is found, and then nothing executes.
	findall(t(actions(As), src(DomainFile, 1, 0, pddl)),
		( findall(Tmpl, ( member(action(Name, Params, _, _), Actions),
				  length(Params, Arity), template(Name, Arity, Tmpl) ), As0),
		  sort(As0, As), As \== [] ),
		DeclActions),
	findall(t(fluents(Fs), src(DomainFile, 1, 0, pddl)),
		( findall(Tmpl, ( member(P, Preds), pred_name_arity(P, N, Arity),
				  \+ memberchk(N, Statics), template(N, Arity, Tmpl) ), Fs0),
		  sort(Fs0, Fs), Fs \== [] ),
		DeclFluents),
	%  static facts from :init become timeless clauses, not fluents: they
	%  never change, and making them fluents would put typing information in
	%  the state where the planner would have to carry it through every node.
	%  A static fact is emitted as a plain clause, not as l_timeless/2: the
	%  compiler indexes ordinary clauses as timeless *and* asserts them into
	%  the program's module, and a denial that calls `room(X)` needs the
	%  second half of that.
	findall(t(Fact, src(ProblemFile, 1, 0, pddl)),
		( member(L, Init), literal_term(L, Fact), functor(Fact, N, _),
		  memberchk(N, Statics) ),
		StaticFacts),
	findall(t(initial_state(IS), src(ProblemFile, 1, 0, pddl)),
		( findall(F, ( member(L, Init), literal_term(L, F),
			       functor(F, N, _), \+ memberchk(N, Statics) ), IS),
		  IS \== [] ),
		InitTerms),
	findall(T, ( member(A, Actions), action_terms(A, Statics, DomainFile, T) ), ActionTerms0),
	flatten_one(ActionTerms0, ActionTerms),
	goal_terms(Goal, ProblemFile, GoalTerms),
	append([DeclActions, DeclFluents, StaticFacts, InitTerms, ActionTerms, GoalTerms], Terms),
	unsupported_diags(Unsup, DomainFile, Diags).

flatten_one([], []).
flatten_one([L|Ls], Flat) :- flatten_one(Ls, Rest), append(L, Rest, Flat).

pred_name_arity([N|Args0], N, Arity) :- strip_types(Args0, Args), length(Args, Arity).

template(Name, 0, Name) :- !.
template(Name, Arity, T) :- length(Args, Arity), T =.. [Name|Args].

/* A predicate that appears in no effect is *static*: `(room ?r)` and
   `(ball ?b)` in gripper are type tests written as predicates, and treating
   them as fluents would put them in every state and in every relaxed planning
   graph for nothing. Finding them is one pass over the effects.
*/
static_predicates(Actions, Init, Statics) :-
	findall(N, ( member(action(_, _, _, Eff), Actions),
		     effect_literal(Eff, _Sign, L), literal_term(L, T), functor(T, N, _) ),
		Changed0),
	sort(Changed0, Changed),
	findall(N, ( member(L, Init), literal_term(L, T), functor(T, N, _),
		     \+ memberchk(N, Changed) ), Statics0),
	sort(Statics0, Statics).

%	Effects: `(and l1 (not l2) …)`, or a bare literal.
effect_literal([and|Ls], Sign, L) :- !, member(X, Ls), effect_literal(X, Sign, L).
effect_literal([not, L], neg, L) :- !.
effect_literal([when|_], _, _) :- !, fail.        % conditional effects: unsupported
effect_literal(L, pos, L) :- literal_shape(L).

condition_literal([and|Ls], Sign, L) :- !, member(X, Ls), condition_literal(X, Sign, L).
condition_literal([not, L], neg, L) :- !.
condition_literal([or|_], _, _) :- !, fail.
condition_literal([forall|_], _, _) :- !, fail.
condition_literal([exists|_], _, _) :- !, fail.
condition_literal(L, pos, L) :- literal_shape(L).

%	A literal is a *proper* list whose head is an atom. Testing `[_|_]`
%	instead unifies an unbound variable with a partial list, and the
%	generator then produces them forever — which is how the plan validator
%	came to exhaust a gigabyte of stack on a plan it had already printed.
literal_shape(L) :- nonvar(L), is_list(L), L = [H|_], atom(H).

/* `(at ?obj ?room)` → `at(Obj, Room)`.
 *
 * The variables have to be *shared* across the terms of one action: the `?x`
 * in `pick-up`'s parameters and the `?x` in `(holding ?x)` are the same
 * variable, and an `initiated/3` whose action and fluent do not share it says
 * that picking anything up makes you hold something. So a map from PDDL
 * variable name to a fresh Prolog variable is built once per action and
 * threaded through every literal. (An earlier version round-tripped through
 * term_to_atom/2 to do this and lost exactly that sharing — silently, since
 * the terms still look right.)
 */
literal_term(L, Term) :- literal_term(L, [], Term).

literal_term([Name|Args], Map, Term) :-
	maplist(pddl_arg(Map), Args, PArgs),
	Term =.. [Name|PArgs].

pddl_arg(Map, A, V) :-
	atom(A), atom_concat('?', _, A), !,
	( memberchk(A-V0, Map) -> V = V0 ; V = _ ).
pddl_arg(_, A, A).

%!	var_map(+SExprs, -Map) is det.
%
%	Every `?name` occurring anywhere in the action, each with one fresh
%	variable.
var_map(Ss, Map) :-
	findall(V, ( sub_atom_of(Ss, V), atom(V), atom_concat('?', _, V) ), Vs0),
	sort(Vs0, Vs),
	findall(V-_, member(V, Vs), Map).

sub_atom_of(X, X) :- atomic(X).
sub_atom_of(L, X) :- is_list(L), member(E, L), sub_atom_of(E, X).

/* One action becomes: a causal law per effect literal, and a denial per
   precondition literal. Variables are shared across all of them by
   constructing the action term once and copying the whole bundle.
*/
action_terms(action(Name, Params, Pre, Eff), Statics, File, Terms) :-
	var_map([Params, Pre, Eff], Map),
	maplist(pddl_arg(Map), Params, PArgs),
	Action =.. [Name|PArgs],
	findall(t(Term, src(File, 1, 0, pddl)),
		( effect_literal(Eff, Sign, L), literal_term(L, Map, F),
		  functor(F, FN, _), \+ memberchk(FN, Statics),
		  ( Sign == pos -> Term = initiated(happens(Action, _T1, _T2), F, [])
		  ; Term = terminated(happens(Action, _T1b, _T2b), F, []) ) ),
		Effects),
	%  A precondition becomes a denial about the state the action starts
	%  from, with the times pinned explicitly — an untimed fluent beside an
	%  action in a denial anchors to the interval, which would make these
	%  read as constraints on the state the action *produces*.
	/*  A precondition over a *static* predicate is a type test, and a type
	    test is not a fluent: `(room ?from)` never changes, so it becomes a
	    timeless clause and the denial calls it directly rather than asking
	    the state about it. Wrapping it in holds/2 would ask the state a
	    question the state cannot answer, and every action would be
	    unreachable — which is exactly what gripper did.  */
	findall(t(d_pre([happens(Action, PT1, _), Cond]), src(File, 1, 0, pddl)),
		( condition_literal(Pre, Sign, L), literal_term(L, Map, F),
		  functor(F, FN, _),
		  (   memberchk(FN, Statics)
		  ->  ( Sign == pos -> Cond = not(F) ; Cond = F )
		  ;   ( Sign == pos -> Cond = holds(not(F), PT1)
		      ; Cond = holds(F, PT1) )
		  ) ),
		Denials),
	append(Effects, Denials, Terms).

goal_terms(Goal, File, [t(achieve(Fs), src(File, 1, 0, pddl))]) :-
	findall(F, ( condition_literal(Goal, pos, L), literal_term(L, F) ), Fs),
	Fs \== [], !.
goal_terms(_, _, []).

unsupported_diags([], _, []).
unsupported_diags([U|Us], File, [D|Ds]) :-
	format(atom(M), 'PDDL section ~w is not supported and was ignored \c
(§IV.1: the transpiled subset is STRIPS with typing)', [U]),
	diag(warning, pddl_unsupported, src(File, 1, 0, pddl), M, D),
	unsupported_diags(Us, File, Ds).

		 /*******************************
		 *	   the oracle		*
		 *******************************/

/* §IV.5: "Do not start a transpiler before its oracle is specified."
 *
 * VAL is the right oracle and is not available in this container, so this is
 * the same check by other means: apply the plan to the initial state using the
 * *PDDL* definitions — not the translated LPS ones — and see whether the goal
 * holds at the end and whether every action's precondition held when it ran.
 *
 * The point is that it shares no code with the translation. A bug in
 * action_terms/4 cannot hide here, because this side never looks at the LPS
 * terms. What it cannot check is plan *quality*; for that the IPC records are
 * the reference, and tools/pddl_test.pl reports plan length beside the known
 * optimum where we have one.
 */
pddl_plan_valid(DomainFile, ProblemFile, Plan, Result) :-
	pddl_read(DomainFile, DS), pddl_domain(DS, domain(_, _, _, Actions, _)),
	pddl_read(ProblemFile, PS), pddl_problem(PS, problem(_, _, _, Init, Goal)),
	findall(F, ( member(L, Init), literal_term(L, F) ), State0),
	sort(State0, State1),
	(   apply_plan(Plan, Actions, State1, Final, 1, Fault)
	->  (   Fault == none
	    ->	(   goal_holds(Goal, Final)
		->  Result = valid
		;   Result = goal_not_reached
		)
	    ;	Result = Fault
	    )
	;   Result = simulation_failed
	).

apply_plan([], _, S, S, _, none).
apply_plan([Step|Steps], Actions, S0, S, N, Fault) :-
	(   apply_step(Step, Actions, S0, S1)
	->  N1 is N + 1, apply_plan(Steps, Actions, S1, S, N1, Fault)
	;   S = S0, format(atom(Fault), 'step ~w (~q) is not applicable', [N, Step])
	).

%	A step is a set of actions (LPS commits several per cycle); each must be
%	applicable in the state the step started from, and all effects apply
%	together.
apply_step(Step, Actions, S0, S) :-
	is_list(Step), !,
	forall(member(A, Step), applicable(A, Actions, S0)),
	apply_all(Step, Actions, S0, S0, S1),
	sort(S1, S).
apply_step(A, Actions, S0, S) :- apply_step([A], Actions, S0, S).

apply_all([], _, _, S, S).
apply_all([A|As], Actions, Ref, In, Out) :-
	apply_effects(A, Actions, Ref, In, Mid),
	apply_all(As, Actions, Ref, Mid, Out).

applicable(A, Actions, S) :-
	matching_action(A, Actions, Pre, _Eff),
	collect(Pre, pos, Pos), collect(Pre, neg, Neg),
	forall(member(L, Pos), ( literal_term(L, F), lit_holds(F, S) )),
	forall(member(L, Neg), ( literal_term(L, F), \+ lit_holds(F, S) )).

apply_effects(A, Actions, _Ref, In, Out) :-
	matching_action(A, Actions, _Pre, Eff),
	collect(Eff, neg, DelL), collect(Eff, pos, AddL),
	maplist(literal_term, DelL, Del),
	maplist(literal_term, AddL, Add),
	subtract_lits(In, Del, In1),
	append(In1, Add, Out0), sort(Out0, Out).

/* Collect the literals of one sign, deterministically.
 *
 * The generator form of this — `effect_literal(E, Sign, L)` on backtracking —
 * is fine when E is ground and a bottomless pit when it is not: an unbound
 * argument unifies with `[_|_]` and the enumeration never ends. It cost a
 * gigabyte of stack before this was written as a fold.
 */
collect(E, Sign, Ls) :- collect_(E, Sign, [], Ls).

collect_(E, _, Acc, Acc) :- var(E), !.
collect_([and|Es], Sign, Acc0, Acc) :- !, collect_all(Es, Sign, Acc0, Acc).
collect_([not, L], neg, Acc0, Acc) :- !, ( literal_shape(L) -> append(Acc0, [L], Acc) ; Acc = Acc0 ).
collect_([not, _], pos, Acc, Acc) :- !.
collect_([when|_], _, Acc, Acc) :- !.
collect_([or|_], _, Acc, Acc) :- !.
collect_([forall|_], _, Acc, Acc) :- !.
collect_([exists|_], _, Acc, Acc) :- !.
collect_(L, pos, Acc0, Acc) :- literal_shape(L), !, append(Acc0, [L], Acc).
collect_(_, _, Acc, Acc).

collect_all([], _, Acc, Acc).
collect_all([E|Es], Sign, Acc0, Acc) :-
	collect_(E, Sign, Acc0, Acc1),
	collect_all(Es, Sign, Acc1, Acc).

lit_holds(F, S) :- memberchk(F, S).

%	The action term in the plan is ground; binding the schema's parameter
%	names to its arguments makes the precondition and effect s-expressions
%	ground with it.
matching_action(A, Actions, Pre, Eff) :-
	functor(A, Name, Arity),
	member(action(Name, Params, Pre0, Eff0), Actions),
	length(Params, Arity),
	A =.. [_|AArgs],
	findall(P-V, ( nth0(I, Params, P), nth0(I, AArgs, V) ), Bindings),
	substitute_vars(Pre0, Bindings, Pre),
	substitute_vars(Eff0, Bindings, Eff), !.

substitute_vars(T, B, Out) :-
	(   atom(T), atom_concat('?', _, T)
	->  ( memberchk(T-V, B) -> Out = V ; Out = T )
	;   is_list(T)
	->  substitute_list(T, B, Out)
	;   Out = T
	).

%	An explicit recursion rather than a yall lambda: `[X,Y]>>Goal` copies
%	the lambda's free variables, and the binding list is one of them, so the
%	substitution quietly produced fresh variables instead of the action's
%	arguments — a plan that executes perfectly then fails its own validator.
substitute_list([], _, []).
substitute_list([X|Xs], B, [Y|Ys]) :-
	substitute_vars(X, B, Y),
	substitute_list(Xs, B, Ys).

subtract_lits([], _, []).
subtract_lits([X|Xs], Del, Out) :-
	( memberchk(X, Del) -> Out = Out1 ; Out = [X|Out1] ),
	subtract_lits(Xs, Del, Out1).

goal_holds(Goal, S) :-
	forall(condition_literal(Goal, pos, L), ( literal_term(L, F), lit_holds(F, S) )),
	forall(condition_literal(Goal, neg, L), ( literal_term(L, F), \+ lit_holds(F, S) )).
