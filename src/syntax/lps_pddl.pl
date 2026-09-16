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
 * Scope, stated rather than discovered (§IV.1): STRIPS with typing, `=`,
 * negative and disjunctive preconditions, `imply`, `exists` and `forall`
 * (in preconditions, in `when` conditions and in the goal), conditional
 * (`when`) and universal (`forall`) effects. Not: numeric fluents, durative
 * actions, axioms, trajectory constraints, preferences. Each of those is
 * *reported* — `pddl_unsupported` warnings, a whole section or the one
 * condition or effect — rather than silently dropped, which is §IV.5's rule
 * about semantic gaps.
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

:- thread_local note/2.            % note(domain|problem, Message)

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
%	Domain = domain(Name, Types, Predicates, Actions, Unsupported, Constants).
%	Types is a list of `Type-Supertype`; Constants and the parameters of
%	each `action(Name, Params, Pre, Eff)` are lists of `Name-Type`, where a
%	Type is an atom, `object` when none was given, or `either(Types)`.
pddl_domain(['define', [domain, Name] | Sections],
	    domain(Name, Types, Preds, Actions, Unsup, Constants)) :-
	findall(T, ( member([':types'|Ts0], Sections), typed_list(Ts0, Ts), member(T, Ts) ), Types),
	findall(C, ( member([':constants'|Cs0], Sections), typed_list(Cs0, Cs), member(C, Cs) ), Constants),
	findall(P, ( member([':predicates'|Ps], Sections), member(P, Ps) ), Preds),
	findall(A, ( member(S, Sections), action_of(S, A) ), Actions),
	findall(U, ( member([K|_], Sections), unsupported_section(K), U = K ), Unsup).

unsupported_section(':functions').
unsupported_section(':durative-action').
unsupported_section(':derived').
unsupported_section(':constraints').

action_of([':action', Name | Rest], action(Name, Params, Pre, Eff)) :-
	kv(Rest, ':parameters', Params0, []), typed_list(Params0, Params),
	kv(Rest, ':precondition', Pre, []),
	kv(Rest, ':effect', Eff, []).

kv(List, Key, Value, _Default) :- append(_, [Key, Value|_], List), !.
kv(_, _, Default, Default).

%!	typed_list(+Items, -Pairs) is det.
%
%	`?x ?y - block ?z` → `['?x'-block, '?y'-block, '?z'-object]`; the type
%	may be `(either t1 t2)`.
typed_list(Items, Pairs) :- typed_list_(Items, [], Pairs).

typed_list_([], Pending, Pairs) :- !,
	findall(X-object, member(X, Pending), Pairs).
typed_list_(['-', T|Rest], Pending, Pairs) :- !,
	type_spec(T, Ty),
	findall(X-Ty, member(X, Pending), P1),
	typed_list_(Rest, [], P2),
	append(P1, P2, Pairs).
typed_list_([X|Rest], Pending, Pairs) :-
	append(Pending, [X], Pending1),
	typed_list_(Rest, Pending1, Pairs).

type_spec([either|Ts], either(Ts)) :- !.
type_spec(T, T).

pairs_names(Pairs, Names) :- findall(N, member(N-_, Pairs), Names).

%!	pddl_problem(+SExpr, -Problem) is det.
%
%	Problem = problem(Name, Domain, Objects, Init, Goal, Unsupported), with
%	Objects a list of `Name-Type`.
pddl_problem(['define', [problem, Name] | Sections],
	     problem(Name, Domain, Objects, Init, Goal, Unsup)) :-
	( member([':domain', Domain], Sections) -> true ; Domain = unknown ),
	findall(O, ( member([':objects'|Os0], Sections), typed_list(Os0, Os), member(O, Os) ), Objects),
	( member([':init'|Init], Sections) -> true ; Init = [] ),
	( member([':goal', Goal], Sections) -> true ; Goal = [and] ),
	findall(K, ( member([K|_], Sections), memberchk(K, [':metric', ':constraints']) ), Unsup).

		 /*******************************
		 *	      types		*
		 *******************************/

/* `:types`, and the `- type` of parameters, objects and constants, are
   enforced, not dropped. Every object gets a timeless fact per type it has,
   its declared type and every supertype (`of_type(rooma, room)`), and a
   typed parameter becomes one more applicability denial,
   `false move(A, B) from T1 to T2, not of_type(A, room).` — the same shape a
   static type predicate like gripper's `(room ?r)` already had.

   A type that every object of the problem has is not checked: the denial
   could never fire, and blocks world, where everything is a block, would
   pay for it in every node the planner expands.
*/

type_ancestors(Type, TypePairs, Ancestors) :-
	type_ancestors_([Type], TypePairs, [], Ancestors).

type_ancestors_([], _, Seen, Seen).
type_ancestors_([T|Ts], Pairs, Seen, All) :-
	(   memberchk(T, Seen)
	->  type_ancestors_(Ts, Pairs, Seen, All)
	;   findall(S, ( member(T-S0, Pairs), type_spec_members(S0, Ss), member(S, Ss) ), Supers),
	    append(Ts, Supers, Ts1),
	    type_ancestors_(Ts1, Pairs, [T|Seen], All)
	).

type_spec_members(either(Ts), Ts) :- !.
type_spec_members(T, [T]).

%	The types an object has: those of its declaration, their ancestors, and
%	`object`.
object_types(Declared, TypePairs, Types) :-
	type_spec_members(Declared, Ds),
	findall(T, ( member(D, Ds), type_ancestors(D, TypePairs, As), member(T, As) ), Ts0),
	sort([object|Ts0], Types).

%	The name of the type predicate: `of_type/2`, unless the domain has a
%	predicate of that name.
type_functor(Preds, F) :-
	(   member([of_type|Args0], Preds), typed_list(Args0, Args), length(Args, 2)
	->  F = pddl_of_type
	;   F = of_type
	).

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
	retractall(note(_, _)),
	pddl_read(DomainFile, DS),
	pddl_read(ProblemFile, PS),
	(   pddl_domain(DS, Domain)
	->  DDiags = []
	;   Domain = domain(unknown, [], [], [], [], []),
	    diag(error, pddl_bad_domain, src(DomainFile, 1, 0, pddl),
		 'could not read the domain', D0),
	    DDiags = [D0]
	),
	(   pddl_problem(PS, Problem)
	->  PDiags = []
	;   Problem = problem(unknown, unknown, [], [], [and], []),
	    diag(error, pddl_bad_problem, src(ProblemFile, 1, 0, pddl),
		 'could not read the problem', D1),
	    PDiags = [D1]
	),
	Domain = domain(_, TypePairs, Preds, Actions, Unsup, Constants),
	Problem = problem(_, _, Objects0, Init, Goal, PUnsup),
	append(Constants, Objects0, Objects),
	static_predicates(Actions, Init, Statics),
	type_functor(Preds, TF),
	findall(O-Ts, ( member(O-D, Objects), object_types(D, TypePairs, Ts) ), ObjTypes),
	Env = env(Statics, TF, ObjTypes),
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
	init_facts(Init, Facts),
	findall(t(Fact, src(ProblemFile, 1, 0, pddl)),
		( member(Fact, Facts), functor(Fact, N, _), memberchk(N, Statics) ),
		StaticFacts),
	findall(t(initial_state(IS), src(ProblemFile, 1, 0, pddl)),
		( findall(F, ( member(F, Facts), functor(F, N, _), \+ memberchk(N, Statics) ), IS),
		  IS \== [] ),
		InitTerms),
	findall(T, ( member(A, Actions), action_terms(A, Env, DomainFile, T) ), ActionTerms0),
	flatten_one(ActionTerms0, ActionTerms),
	goal_terms(Goal, Env, Preds, ProblemFile, GoalTerms),
	%  The type facts, for the types the translation actually asks about.
	append([ActionTerms, GoalTerms], Using),
	findall(Ty, ( sub_term(S, Using), compound(S), S =.. [TF, _, Ty0], atom(Ty0), Ty = Ty0 ), Tys0),
	sort(Tys0, Tys),
	findall(t(Fact, src(ProblemFile, 1, 0, pddl)),
		( member(Ty, Tys), member(O-OTs, ObjTypes), memberchk(Ty, OTs), Fact =.. [TF, O, Ty] ),
		TypeFacts),
	append([DeclActions, DeclFluents, StaticFacts, TypeFacts, InitTerms, ActionTerms, GoalTerms], Terms),
	unsupported_diags(Unsup, DomainFile, UDiags),
	unsupported_diags(PUnsup, ProblemFile, UPDiags),
	findall(D, ( note(File0, M), ( File0 == problem -> File = ProblemFile ; File = DomainFile ),
		     diag(warning, pddl_unsupported, src(File, 1, 0, pddl), M, D) ), NDiags0),
	list_to_set(NDiags0, NDiags),
	append([DDiags, PDiags, UDiags, UPDiags, NDiags], Diags).

%	A construct that cannot be translated is said, once, in a warning. Where
%	is `domain` or `problem`.
say(Where, Fmt, Args0) :-
	maplist(sexpr_text, Args0, Args),
	format(atom(M), Fmt, Args),
	( note(Where, M) -> true ; assertz(note(Where, M)) ).

%	An s-expression as PDDL writes it: `(increase (total-cost) 1)`.
sexpr_text(X, X) :- \+ is_list(X), !.
sexpr_text(L, T) :-
	maplist(sexpr_text, L, Ts),
	atomic_list_concat(Ts, ' ', Inner),
	format(atom(T), '(~w)', [Inner]).

flatten_one([], []).
flatten_one([L|Ls], Flat) :- flatten_one(Ls, Rest), append(L, Rest, Flat).

pred_name_arity([N|Args0], N, Arity) :- typed_list(Args0, Args), length(Args, Arity).

template(Name, 0, Name) :- !.
template(Name, Arity, T) :- length(Args, Arity), T =.. [Name|Args].

%	:init — literals, minus the numeric `(= (f) 3)` and timed initial
%	literals, which are said and left out.
init_facts(Init, Facts) :-
	findall(F, ( member(L, Init), init_fact(L, F) ), Facts).

init_fact(L, F) :-
	(   literal_shape(L)
	->  literal_term(L, F)
	;   L = [=|_]
	->  say(problem, 'numeric fluent ~w in :init is not supported and was ignored (§IV.1: no numeric fluents)', [L]),
	    fail
	;   say(problem, ':init entry ~w is not a literal and was ignored', [L]),
	    fail
	).

/* A predicate that appears in no effect is *static*: `(room ?r)` and
   `(ball ?b)` in gripper are type tests written as predicates, and treating
   them as fluents would put them in every state and in every relaxed planning
   graph for nothing. Finding them is one pass over the effects, conditional
   and universal ones included.
*/
static_predicates(Actions, Init, Statics) :-
	findall(N, ( member(action(_, _, _, Eff), Actions), effect_name(Eff, N) ), Changed0),
	sort(Changed0, Changed),
	findall(N, ( member(L, Init), literal_shape(L), L = [N|_],
		     \+ memberchk(N, Changed) ), Statics0),
	sort(Statics0, Statics).

effect_name(E, _) :- var(E), !, fail.
effect_name([and|Es], N) :- !, member(E, Es), effect_name(E, N).
effect_name([not, L], N) :- !, effect_name(L, N).
effect_name([when, _, E], N) :- !, effect_name(E, N).
effect_name([forall, _, E], N) :- !, effect_name(E, N).
effect_name(L, N) :- literal_shape(L), L = [N|_], \+ numeric_op(N).

numeric_op(increase). numeric_op(decrease). numeric_op(assign).
numeric_op('scale-up'). numeric_op('scale-down').

comparison_op(<). comparison_op(>). comparison_op(<=). comparison_op(>=).

%	A literal is a *proper* list whose head is an atom and whose arguments
%	are names. Testing `[_|_]` instead unifies an unbound variable with a
%	partial list, and the generator then produces them forever — which is how
%	the plan validator came to exhaust a gigabyte of stack on a plan it had
%	already printed.
literal_shape(L) :-
	nonvar(L), is_list(L), L = [H|Args], atom(H),
	\+ memberchk(H, [and, or, not, imply, exists, forall, when, =]),
	\+ numeric_op(H), \+ comparison_op(H),
	forall(member(A, Args), atom(A)).

/* `(at ?obj ?room)` → `at(Obj, Room)`.
 *
 * The variables have to be *shared* across the terms of one action: the `?x`
 * in `pick-up`'s parameters and the `?x` in `(holding ?x)` are the same
 * variable, and an `initiated/3` whose action and fluent do not share it says
 * that picking anything up makes you hold something. So a map from PDDL
 * variable name to a fresh Prolog variable is built once per action and
 * threaded through every literal; a quantifier puts its own variables in
 * front of it. (An earlier version round-tripped through term_to_atom/2 to
 * do this and lost exactly that sharing — silently, since the terms still
 * look right.)
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

/* Conditions, in disjunctive normal form.

   dnf(+Formula, +Polarity, +Ctx, -Disjuncts): Disjuncts is a list of
   conjunctions, each a list of LPS conditions, whose disjunction is Formula
   (Polarity `pos`) or its negation (`neg`). A precondition P becomes one
   denial per disjunct of `not P` — which for a conjunction of literals is
   the one-denial-per-literal translation this module always had — and a
   `when` condition one causal law per disjunct of it.

     (or A B)            alternatives: disjuncts, and `not (or A B)` a
			 conjunction of both negations
     (exists (?v - t) A) a variable, generated by its type: of_type(V, t)
     not (exists …)      a negation as failure over the conjunction,
			 holds(not([of_type(V, t), …]), T)
     (forall (?v - t) A) not (exists (?v - t) (not A))
     (imply A B)         (or (not A) B)
     (= ?x ?y)           X == Y, a comparison of names, not a state

   Numeric comparisons are not LPS2's to translate here: each is said, and
   read as satisfied. Ctx = ctx(Map, Env, Time, Where).
*/
%	An empty condition, `()`, is true: its negation has no disjunct.
dnf(F, Pol, _, Ds) :- ( var(F) ; F == [] ), !, ( Pol == pos -> Ds = [[]] ; Ds = [] ).
dnf([and|Fs], pos, C, Ds) :- !, dnf_each(Fs, pos, C, Dss), cross(Dss, Ds).
dnf([and|Fs], neg, C, Ds) :- !, dnf_each(Fs, neg, C, Dss), append(Dss, Ds).
dnf([or|Fs], pos, C, Ds) :- !, dnf_each(Fs, pos, C, Dss), append(Dss, Ds).
dnf([or|Fs], neg, C, Ds) :- !, dnf_each(Fs, neg, C, Dss), cross(Dss, Ds).
dnf([not, F], Pol, C, Ds) :- !, flip(Pol, Pol1), dnf(F, Pol1, C, Ds).
dnf([imply, A, B], Pol, C, Ds) :- !, dnf([or, [not, A], B], Pol, C, Ds).
dnf([exists, Vs, F], pos, C, Ds) :- !,
	quantified(Vs, C, C1, GenAlts),
	dnf(F, pos, C1, Ds0),
	cross([GenAlts, Ds0], Ds1),
	maplist(ordered, Ds1, Ds).
dnf([exists, Vs, F], neg, C, [Conj]) :- !,
	C = ctx(_, _, T, _),
	quantified(Vs, C, C1, GenAlts),
	dnf(F, pos, C1, Ds0),
	cross([GenAlts, Ds0], Ds1),
	maplist(naf(T), Ds1, Conj).
dnf([forall, Vs, F], pos, C, Ds) :- !, dnf([exists, Vs, [not, F]], neg, C, Ds).
dnf([forall, Vs, F], neg, C, Ds) :- !, dnf([exists, Vs, [not, F]], pos, C, Ds).
dnf([=, A, B], Pol, C, Ds) :- atom(A), atom(B), !,
	C = ctx(Map, _, _, _),
	pddl_arg(Map, A, X), pddl_arg(Map, B, Y),
	( Pol == pos -> Ds = [[X == Y]] ; Ds = [[X \== Y]] ).
dnf([Op|Args], Pol, C, Ds) :-
	( Op == (=) ; comparison_op(Op) ), length(Args, 2), !,
	C = ctx(_, _, _, Where),
	say(domain, 'numeric condition ~w in ~w is not supported and was read as satisfied (§IV.1: no numeric fluents)',
	    [[Op|Args], Where]),
	( Pol == pos -> Ds = [[]] ; Ds = [] ).
dnf(L, Pol, C, Ds) :- literal_shape(L), !,
	C = ctx(Map, env(Statics, _, _), T, _),
	literal_term(L, Map, F),
	functor(F, N, _),
	(   memberchk(N, Statics)
	->  ( Pol == pos -> Ds = [[F]] ; Ds = [[not(F)]] )
	;   ( Pol == pos -> Ds = [[holds(F, T)]] ; Ds = [[holds(not(F), T)]] )
	).
dnf(F, Pol, C, Ds) :-
	C = ctx(_, _, _, Where),
	say(domain, 'condition ~w in ~w is not supported and was read as satisfied', [F, Where]),
	( Pol == pos -> Ds = [[]] ; Ds = [] ).

dnf_each([], _, _, []).
dnf_each([F|Fs], Pol, C, [D|Ds]) :- dnf(F, Pol, C, D), dnf_each(Fs, Pol, C, Ds).

flip(pos, neg).
flip(neg, pos).

%	The conjunctions of one disjunct from each list.
%	No findall here or anywhere below: it copies, and a copied condition no
%	longer shares its variables with the action it is a condition of.
cross([], [[]]).
cross([Ds|Dss], Out) :-
	cross(Dss, Rest),
	cross_one(Ds, Rest, Out).

cross_one([], _, []).
cross_one([D|Ds], Rest, Out) :-
	maplist(append(D), Rest, Out1),
	cross_one(Ds, Rest, Out2),
	append(Out1, Out2, Out).

naf(T, D0, holds(not(D), T)) :- ordered(D0, D).

%	Quantified variables: fresh, in front of the map, each generated by its
%	type (`object` when it has none: every object has that one).
%	GenAlts is a list of alternative generator conjunctions: one, unless a
%	variable has an `(either …)` type, which is a disjunction of types.
quantified(Vs0, ctx(Map, Env, T, W), ctx(Map1, Env, T, W), GenAlts) :-
	typed_list(Vs0, Vs),
	Env = env(_, TF, _),
	quantified_vars(Vs, TF, New, Altss),
	append(New, Map, Map1),
	cross(Altss, GenAlts).

quantified_vars([], _, [], []).
quantified_vars([V-Ty|Vs], TF, [V-X|New], [Alts|Altss]) :-
	type_members_list(Ty, Ts),
	maplist(type_goal_alt(TF, X), Ts, Alts),
	quantified_vars(Vs, TF, New, Altss).

type_goal_alt(TF, X, T, [G]) :- G =.. [TF, X, T].
type_test(TF, X, T, not(G)) :- G =.. [TF, X, T].

type_members_list(Ty, Ts) :- type_spec_members(Ty, Ts).

%	Generators first, then what binds from the state, then the tests: a
%	negation or a comparison over a variable nothing has bound yet asks the
%	wrong question.
ordered(Conds, Ordered) :-
	partition(cond_rank(0), Conds, R0, Rest0),
	partition(cond_rank(1), Rest0, R1, R2),
	append([R0, R1, R2], Ordered).

cond_rank(0, C) :- compound(C), functor(C, F, 2), ( F == of_type ; F == pddl_of_type ), !.
cond_rank(1, holds(F, _)) :- nonvar(F), F \= not(_), !.
cond_rank(1, C) :- compound(C), C \= not(_), C \= holds(_, _), C \= (_ == _), C \= (_ \== _), !.

/* One action becomes: a causal law per effect literal (per disjunct of its
   condition, for a conditional one), a denial per disjunct of the negated
   precondition, and a denial per typed parameter. Variables are shared
   across all of them by constructing the action term once and copying the
   whole bundle.
*/
action_terms(action(Name, Params, Pre, Eff), Env, File, Terms) :-
	pairs_names(Params, PNames),
	var_map([PNames, Pre, Eff], Map),
	maplist(pddl_arg(Map), PNames, PArgs),
	Action =.. [Name|PArgs],
	Src = src(File, 1, 0, pddl),
	effect_laws(Eff, [], ctx(Map, Env, T1, Name), Laws),
	findall(t(Term, Src),
		( member(law(Sign, F, Conds), Laws),
		  ( Sign == pos -> Term = initiated(happens(Action, T1, _T2), F, Conds)
		  ; Term = terminated(happens(Action, T1, _T2b), F, Conds) ) ),
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
	dnf(Pre, neg, ctx(Map, Env, PT1, Name), NegPre),
	findall(t(d_pre([happens(Action, PT1, _)|D]), Src),
		( member(D0, NegPre), ordered(D0, D) ),
		Denials),
	Env = env(_, TF, ObjTypes),
	findall(t(d_pre([happens(Action, _, _)|Tests]), Src),
		( member(P-Ty, Params),
		  type_checked(P, Ty, Pre, ObjTypes),
		  memberchk(P-X, Map),
		  type_spec_members(Ty, Ts), maplist(type_test(TF, X), Ts, Tests) ),
		TypeDenials),
	append([Effects, Denials, TypeDenials], Terms).

/*  A parameter's type is checked unless every object has it — and even then
    when no precondition mentions the parameter, because the type is then the
    only thing that says what the parameter can be: `(:action light
    :parameters (?x) :effect (lit ?x))` gets `not of_type(X, object)`, and the
    planner has objects to try.  */
type_checked(P, Ty, Pre, ObjTypes) :-
	(   \+ sub_atom_of(Pre, P)
	->  true
	;   Ty \== object,
	    \+ every_object_has(Ty, ObjTypes)
	).

every_object_has(Ty, ObjTypes) :-
	type_spec_members(Ty, Ts),
	forall(member(_-OTs, ObjTypes), ( member(T, Ts), memberchk(T, OTs) )).

%	effect_laws(+Effect, +Conds, +Ctx, -Laws): `law(pos|neg, Fluent, Conds)`.
effect_laws(E, _, _, []) :- var(E), !.
effect_laws([], _, _, []) :- !.
effect_laws([and|Es], Cs, C, Laws) :- !,
	effect_laws_list(Es, Cs, C, Laws).
effect_laws([not, L], Cs, C, Laws) :- literal_shape(L), !,
	C = ctx(Map, env(Statics, _, _), _, _),
	literal_term(L, Map, F), functor(F, N, _),
	( memberchk(N, Statics) -> Laws = [] ; Laws = [law(neg, F, Cs)] ).
effect_laws([forall, Vs, E], Cs, C, Laws) :- !,
	quantified(Vs, C, C1, GenAlts),
	effect_laws_when(GenAlts, Cs, E, C1, Laws).
effect_laws([when, Cond, E], Cs, C, Laws) :- !,
	dnf(Cond, pos, C, Ds),
	effect_laws_when(Ds, Cs, E, C, Laws).
effect_laws([Op|Args], _, C, []) :- numeric_op(Op), !,
	C = ctx(_, _, _, Where),
	say(domain, 'numeric effect ~w in ~w is not supported and was ignored (§IV.1: no numeric fluents)',
	    [[Op|Args], Where]).
effect_laws(L, Cs, C, Laws) :- literal_shape(L), !,
	C = ctx(Map, env(Statics, _, _), _, _),
	literal_term(L, Map, F), functor(F, N, _),
	( memberchk(N, Statics) -> Laws = [] ; ordered(Cs, Cs1), Laws = [law(pos, F, Cs1)] ).
effect_laws(E, _, C, []) :-
	C = ctx(_, _, _, Where),
	say(domain, 'effect ~w in ~w is not supported and was ignored', [E, Where]).

effect_laws_list([], _, _, []).
effect_laws_list([E|Es], Cs, C, Laws) :-
	effect_laws(E, Cs, C, L1),
	effect_laws_list(Es, Cs, C, L2),
	append(L1, L2, Laws).

effect_laws_when([], _, _, _, []).
effect_laws_when([D|Ds], Cs, E, C, Laws) :-
	append(Cs, D, Cs1),
	effect_laws(E, Cs1, C, L1),
	effect_laws_when(Ds, Cs, E, C, L2),
	append(L1, L2, Laws).

/* The goal.

   A conjunction of literals, positive or negative, is an `achieve` of its
   fluents, `not(F)` for a negative one. Anything else — `or`, `exists`,
   `forall`, a static predicate — is an intensional fluent `goal_reached`
   with one clause per disjunct of the goal, and the `achieve` asks for that.
*/
goal_terms(Goal, Env, Preds, File, Terms) :-
	Src = src(File, 1, 0, pddl),
	var_map([Goal], Map),
	dnf(Goal, pos, ctx(Map, Env, T, ':goal'), Ds),
	(   Ds == []
	->  say(problem, 'the :goal can never hold', []),
	    Terms = []
	;   Ds = [D], D \== [], maplist(goal_fluent(T), D, Fs)
	->  Terms = [t(achieve(Fs), Src)]
	;   Ds = [[]]
	->  Terms = []
	;   goal_name(Preds, G),
	    findall(t(l_int(holds(G, T), D1), Src), ( member(D, Ds), ordered(D, D1) ), Clauses),
	    append(Clauses, [t(achieve([G]), Src)], Terms)
	).

goal_fluent(T, holds(F, T0), F) :- T0 == T, nonvar(F), ( F = not(G) -> ground(G) ; ground(F) ).

goal_name(Preds, G) :-
	(   member([goal_reached|_], Preds) -> G = pddl_goal_reached ; G = goal_reached ).

unsupported_diags([], _, []).
unsupported_diags([U|Us], File, [D|Ds]) :-
	format(atom(M), 'PDDL section ~w is not supported and was ignored \c
(§IV.1: the transpiled subset is STRIPS with typing, negative and \c
disjunctive preconditions, quantifiers and conditional effects)', [U]),
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
 * terms. It evaluates PDDL's formulas directly — `and`, `or`, `not`,
 * `imply`, `exists` and `forall` over the objects of the problem, `=`,
 * parameter types, and conditional and universal effects — and, like the
 * translation, reads a numeric condition as satisfied and a numeric effect
 * as nothing. What it cannot check is plan *quality*; for that the IPC
 * records are the reference, and tools/pddl_test.pl reports plan length
 * beside the known optimum where we have one.
 */
pddl_plan_valid(DomainFile, ProblemFile, Plan, Result) :-
	pddl_read(DomainFile, DS), pddl_domain(DS, domain(_, TypePairs, _, Actions, _, Constants)),
	pddl_read(ProblemFile, PS), pddl_problem(PS, problem(_, _, Objects0, Init, Goal, _)),
	append(Constants, Objects0, Objects),
	findall(O-Ts, ( member(O-D, Objects), object_types(D, TypePairs, Ts) ), World),
	findall(F, ( member(L, Init), literal_shape(L), literal_term(L, F) ), State0),
	sort(State0, State1),
	(   apply_plan(Plan, Actions, World, State1, Final, 1, Fault)
	->  (   Fault == none
	    ->	(   f_holds(Goal, [], World, Final)
		->  Result = valid
		;   Result = goal_not_reached
		)
	    ;	Result = Fault
	    )
	;   Result = simulation_failed
	).

apply_plan([], _, _, S, S, _, none).
apply_plan([Step|Steps], Actions, W, S0, S, N, Fault) :-
	(   apply_step(Step, Actions, W, S0, S1)
	->  N1 is N + 1, apply_plan(Steps, Actions, W, S1, S, N1, Fault)
	;   S = S0, format(atom(Fault), 'step ~w (~q) is not applicable', [N, Step])
	).

%	A step is a set of actions (LPS commits several per cycle); each must be
%	applicable in the state the step started from, and all effects apply
%	together, deletions before additions.
apply_step(Step, Actions, W, S0, S) :-
	is_list(Step), !,
	forall(member(A, Step), applicable(A, Actions, W, S0)),
	foldl(step_effects(Actions, W, S0), Step, []-[], Del-Add),
	subtract_lits(S0, Del, S1),
	append(S1, Add, S2),
	sort(S2, S).
apply_step(A, Actions, W, S0, S) :- apply_step([A], Actions, W, S0, S).

step_effects(Actions, W, S0, A, Del0-Add0, Del-Add) :-
	matching_action(A, Actions, W, Bindings, _Pre, Eff),
	effects(Eff, Bindings, W, S0, Del1, Add1),
	append(Del0, Del1, Del), append(Add0, Add1, Add).

applicable(A, Actions, W, S) :-
	matching_action(A, Actions, W, Bindings, Pre, _Eff),
	f_holds(Pre, Bindings, W, S).

%	The action in the plan is ground; its schema's parameter names are bound
%	to its arguments, and each argument must have its parameter's type.
matching_action(A, Actions, W, Bindings, Pre, Eff) :-
	functor(A, Name, Arity),
	member(action(Name, Params, Pre, Eff), Actions),
	length(Params, Arity),
	A =.. [_|AArgs],
	findall(P-V, ( nth0(I, Params, P-_), nth0(I, AArgs, V) ), Bindings),
	forall(( nth0(I, Params, _-Ty), nth0(I, AArgs, V) ), has_type(V, Ty, W)), !.

has_type(_, object, _) :- !.
has_type(V, Ty, W) :-
	memberchk(V-Ts, W),
	type_spec_members(Ty, Want),
	member(T, Want), memberchk(T, Ts), !.

%	f_holds(+Formula, +Bindings, +World, +State): PDDL's semantics, directly.
f_holds(F, _, _, _) :- var(F), !.
f_holds([], _, _, _) :- !.
f_holds([and|Fs], B, W, S) :- !, forall(member(F, Fs), f_holds(F, B, W, S)).
f_holds([or|Fs], B, W, S) :- !, member(F, Fs), f_holds(F, B, W, S), !.
f_holds([not, F], B, W, S) :- !, \+ f_holds(F, B, W, S).
f_holds([imply, X, Y], B, W, S) :- !, ( f_holds(X, B, W, S) -> f_holds(Y, B, W, S) ; true ).
f_holds([exists, Vs0, F], B, W, S) :- !,
	typed_list(Vs0, Vs),
	instance_bindings(Vs, W, B, B1),
	f_holds(F, B1, W, S), !.
f_holds([forall, Vs0, F], B, W, S) :- !,
	typed_list(Vs0, Vs),
	forall(instance_bindings(Vs, W, B, B1), f_holds(F, B1, W, S)).
f_holds([=, X, Y], B, _, _) :- atom(X), atom(Y), !,
	bound_arg(B, X, VX), bound_arg(B, Y, VY), VX == VY.
f_holds([Op|_], _, _, _) :- ( Op == (=) ; comparison_op(Op) ), !.   % numeric: read as satisfied
f_holds(L, B, _, S) :- literal_shape(L), !,
	L = [N|Args], maplist(bound_arg(B), Args, Vs), F =.. [N|Vs],
	memberchk(F, S).

bound_arg(B, A, V) :- ( memberchk(A-V0, B) -> V = V0 ; V = A ).

instance_bindings([], _, B, B).
instance_bindings([V-Ty|Vs], W, B0, B) :-
	member(O-_, W), has_type(O, Ty, W),
	instance_bindings(Vs, W, [V-O|B0], B).

%	effects(+Effect, +Bindings, +World, +PreState, -Deleted, -Added)
effects(E, B, W, S, Del, Add) :-
	findall(Sign-F, effect_instance(E, B, W, S, Sign, F), Es),
	findall(F, member(del-F, Es), Del),
	findall(F, member(add-F, Es), Add).

effect_instance(E, _, _, _, _, _) :- var(E), !, fail.
effect_instance([and|Es], B, W, S, Sign, F) :- !, member(E, Es), effect_instance(E, B, W, S, Sign, F).
effect_instance([not, L], B, _, _, del, F) :- literal_shape(L), !,
	L = [N|Args], maplist(bound_arg(B), Args, Vs), F =.. [N|Vs].
effect_instance([when, C, E], B, W, S, Sign, F) :- !,
	f_holds(C, B, W, S), effect_instance(E, B, W, S, Sign, F).
effect_instance([forall, Vs0, E], B, W, S, Sign, F) :- !,
	typed_list(Vs0, Vs),
	instance_bindings(Vs, W, B, B1),
	effect_instance(E, B1, W, S, Sign, F).
effect_instance(L, B, _, _, add, F) :- literal_shape(L), !,
	L = [N|Args], maplist(bound_arg(B), Args, Vs), F =.. [N|Vs].

subtract_lits([], _, []).
subtract_lits([X|Xs], Del, Out) :-
	( memberchk(X, Del) -> Out = Out1 ; Out = [X|Out1] ),
	subtract_lits(Xs, Del, Out1).
