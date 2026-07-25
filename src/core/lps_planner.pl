/* lps_planner.pl — declarative planning mode (§I.7).

   The claim §I.7 makes, and this module implements:

   > Planning is not a dialect. It is a search strategy over unchanged LPS.
   > Same program, same constraints, same causal laws — the only difference is
   > whether an unreducible goal falls through to hand-written decomposition or
   > to the planner.

   So there is exactly one new construct, `achieve`, and *no* new semantics for
   `false`. The planner consumes the denials the reactive engine already
   consumes; it does not reinterpret them.

   The four-way static classification of §I.7.4 is what makes the search
   tractable rather than a generate-and-test:

     actions only                     → prune action *sets* (interference)
     one action + current fluents     → applicability; generate, don't filter
     fluents at the result state      → prune successor states
     anything else                    → test-and-reject after generation

   The fourth row is the correctness backstop: whatever the analysis cannot
   classify is still checked, just later and more expensively.

   The non-obvious part is that **LPS cycles allow several actions at once**
   — the goat trace has `row(south,north)` and `transport(goat,south,north)`
   in the same cycle — so this is not STRIPS. Each search step chooses a *set*
   of actions that is individually applicable, jointly non-interfering, and
   whose resulting state satisfies every prospective constraint. Branching is
   over subsets.

   §I.7.5 is the integration decision, and it is what keeps `.lpst` testing
   working for planned programs: the planner does not replace the cycle. It
   produces a list of action sets, one per cycle, and those are handed to the
   ordinary cycle as goals with pinned times. Preconditions and integrity
   constraints are then applied by the engine exactly as they are for a
   hand-written program, and an execution-time failure surfaces normally
   (§I.7.6 decides what to do about it).
*/

:- module(lps_planner, [
	plan_for/4,              % +Program, +Goals, +Options, -Plan
	plan_goals/2,            % +Program, -Goals
	plan_to_session_goals/4, % +Plan, +StartTime, +Options, -Goals
	classify_denials/2,      % +Program, -Classified
	planning_mode/1          % +Program
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(lps_ops).
:- use_module(lps_store).
:- use_module(lps_program).
:- use_module(lps_terms).
:- use_module(lps_query).

%!	planning_mode(+Program) is semidet.
planning_mode(P) :- prog_setting(P, engine, planning).

%!	plan_goals(+Program, -Goals) is semidet.
%
%	The conjunction of fluents an `achieve` asks for.
plan_goals(P, Goals) :-
	prog_module(P, M),
	catch(M:achieve(Goals), _, fail).

		 /*******************************
		 *   static denial classification *
		 *******************************/

%!	classify_denials(+Program, -Classified) is det.
%
%	Classified is a list of `denial(Kind, Conditions)` with Kind one of
%	`interference`, `applicability(ActionTemplate)`, `prospective` or
%	`other`. The classification is *static* — it depends on the shape of the
%	clause, not on any state — so it is computed once per program.
classify_denials(P, Classified) :-
	findall(denial(Kind, Conds),
		( p_d_pre(P, Conds), denial_kind(Conds, Kind) ),
		Classified).

denial_kind(Conds, Kind) :-
	findall(A, member(happens(A, _, _), Conds), Actions),
	findall(holds(F, T), member(holds(F, T), Conds), Fluents),
	length(Actions, NA),
	(   NA >= 2, Fluents == []
	->  Kind = interference
	;   NA =:= 1, Fluents \== [], prospective_conditions(Conds)
	->  Kind = prospective
	;   NA =:= 0, Fluents \== [], prospective_conditions(Conds)
	->  Kind = prospective
	;   NA =:= 1, Actions = [A]
	->  Kind = applicability(A)
	;   NA >= 2
	->  Kind = interference
	;   Kind = other
	).

%	The prospective form of §0.5: a fluent whose time is the *end* of an
%	action interval, i.e. the state the action would produce.
prospective_conditions(Conds) :-
	member(happens(_, _, Next), Conds),
	member(holds(_, T), Conds),
	T == Next, !.
prospective_conditions(Conds) :-
	\+ member(happens(_, _, _), Conds),
	member(holds(_, _), Conds).

		 /*******************************
		 *	     the search	*
		 *******************************/

%!	plan_for(+Program, +Goals, +Options, -Plan) is semidet.
%
%	Plan is a list of action sets, one per cycle. BFS, so it is complete and
%	optimal in plan length — adequate for puzzle scale, which is what the
%	examples are (§I.7.4 stage 1). A relaxed-plan heuristic is stage 2 and
%	is not needed to make the declarative goat work.
plan_for(P, Goals, Options, Plan) :-
	horizon(Options, Horizon),
	st_state_list(State0),
	classify_denials(P, Denials),
	save_store_state(Saved),
	setup_call_cleanup(
	    true,
	    bfs([node(State0, [])], [State0], P, Goals, Denials, Horizon, Plan),
	    restore_store_state(Saved)).

horizon(Options, H) :- memberchk(horizon(H), Options), !.
horizon(_, 12).

max_concurrency(Options, N) :- memberchk(max_concurrency(N), Options), !.
max_concurrency(_, 3).

save_store_state(state(S, N)) :- st_state_list(S), st_now(N).
restore_store_state(state(S, N)) :- st_set_state(S), st_set_now(N).

bfs([node(State, Plan0)|_], _Visited, P, Goals, _D, _H, Plan) :-
	with_state(State, goals_hold(P, Goals)), !,
	reverse(Plan0, Plan).
bfs([node(_, Plan0)|Rest], Visited, P, Goals, D, H, Plan) :-
	length(Plan0, L), L >= H, !,
	bfs(Rest, Visited, P, Goals, D, H, Plan).
bfs([node(State, Plan0)|Rest], Visited, P, Goals, D, H, Plan) :-
	successors(P, State, D, Succs),
	fresh(Succs, Visited, Plan0, New, Visited1),
	append(Rest, New, Queue),
	bfs(Queue, Visited1, P, Goals, D, H, Plan).

fresh([], Visited, _, [], Visited).
fresh([ActionSet-S|Ss], Visited, Plan0, New, Visited1) :-
	msort(S, Key),
	(   member(V, Visited), msort(V, Key)
	->  fresh(Ss, Visited, Plan0, New, Visited1)
	;   New = [node(S, [ActionSet|Plan0])|New1],
	    fresh(Ss, [S|Visited], Plan0, New1, Visited1)
	).

goals_hold(_P, []) :- !.
goals_hold(P, [G|Gs]) :- !, goals_hold(P, G), goals_hold(P, Gs).
goals_hold(_P, G) :- st_now(T), dc_query(holds(G, T)).

%	Evaluate a query against a hypothetical state. This is §I.6's fork in
%	miniature: the state is a value, so trying one out costs a rebind.
with_state(State, Goal) :-
	st_state_list(Old),
	setup_call_cleanup(st_set_state(State), once(Goal), st_set_state(Old)).

		 /*******************************
		 *	   successors		*
		 *******************************/

%!	successors(+Program, +State, +Denials, -Pairs) is det.
%
%	Pairs are ActionSet-NextState. An action set must be individually
%	applicable, jointly free of interference, and must not produce a state
%	that a prospective denial rejects.
successors(P, State, Denials, Pairs) :-
	with_state(State, applicable_actions(P, Denials, Applicable)),
	prog_setting(P, engine_options, Options0),
	( is_list(Options0) -> Options = Options0 ; Options = [] ),
	max_concurrency(Options, MaxC),
	findall(Set, action_subset(Applicable, MaxC, Set), Sets0),
	include([S]>>(S \== []), Sets0, Sets),
	findall(Set-Next,
		( member(Set, Sets),
		  \+ interferes(Set, Denials),
		  apply_actions(P, State, Set, Next),
		  \+ prospectively_rejected(P, Set, Next, Denials) ),
		Pairs).

%	Subsets of at most MaxC elements, largest first: a step that does more
%	is preferred, which keeps plans short without needing a heuristic.
action_subset(Actions, MaxC, Set) :-
	length(Actions, N),
	Max is min(MaxC, N),
	between(0, Max, K0), K is Max - K0,
	length(Set, K),
	subset_of(Set, Actions).

subset_of([], _).
subset_of([X|Xs], [Y|Ys]) :-
	( X = Y, subset_of(Xs, Ys) ; subset_of([X|Xs], Ys) ).

/* Row 2 of §I.7.4: *generate* only applicable actions rather than enumerate
   every ground instance and reject.

   Candidates come from the action theory itself — the causal laws — not from
   a cross product over the declared actions. Solving a law's own requirements
   against the current state binds most of the action's arguments for free:

     transport(O,L1,L2) updates L1 to L2 in loc(O,L1)

   `loc(O,L1)` must hold, which binds O and L1 to something actually in the
   state; only L2 is left, and it ranges over the values seen in *that
   argument position of that fluent* anywhere in the program. That typed
   universe is what stops `transport(goat, south, cabbage)` from being
   considered at all.

   The alternative — a universe of every constant in the program — is what
   makes naive grounding explode, and it is not merely slower: it generates
   nonsense actions whose successor states then have to be deduplicated.
*/
applicable_actions(P, Denials, Applicable) :-
	findall(A,
		( candidate_action(P, A),
		  ground(A),
		  changes_state(P, A),
		  \+ blocked_now(A, Denials) ),
		As),
	sort(As, Applicable).

candidate_action(P, A) :-
	p_updated(P, happens(A, _, _), TFl, Old-New, Cond),
	st_state(TFl),
	holds_all(Cond),
	bind_replacements(P, TFl, Old, New).
candidate_action(P, A) :-
	( p_initiated(P, happens(A, _, _), Fl, Cond)
	; p_terminated(P, happens(A, _, _), Fl, Cond)
	),
	holds_all(Cond),
	nonvar(Fl),
	bind_remaining(P, A).

%	`Old-New` may be a single subterm or a list of them; each New ranges
%	over the values seen where the matching Old sits in the fluent.
bind_replacements(P, TFl, Old, New) :-
	is_list(Old), !,
	bind_replacement_list(P, TFl, Old, New).
bind_replacements(P, TFl, Old, New) :-
	position_universe(P, TFl, Old, Values),
	member(New, Values).

bind_replacement_list(_, _, [], []).
bind_replacement_list(P, TFl, [O|Os], [N|Ns]) :-
	position_universe(P, TFl, O, Values),
	member(N, Values),
	bind_replacement_list(P, TFl, Os, Ns).

%	Every atomic value seen at the position `Old` occupies in this fluent,
%	anywhere in the program: the state, the initial state, the denials, the
%	causal laws and the `achieve` goal. The goal matters — `north` appears
%	nowhere in the goat's initial state.
position_universe(P, Fluent, Old, Values) :-
	functor(Fluent, F, N),
	argument_position(Fluent, Old, Pos),
	findall(V,
		( program_fluent_instance(P, Inst),
		  functor(Inst, F, N),
		  arg(Pos, Inst, V),
		  atomic(V) ),
		Vs),
	sort(Vs, Values).

argument_position(Fluent, Old, Pos) :-
	compound(Fluent),
	functor(Fluent, _, N),
	between(1, N, Pos),
	arg(Pos, Fluent, A),
	A == Old, !.

%	Anywhere a fluent term appears in the program, so the universe includes
%	values the initial state never mentions.
program_fluent_instance(_P, F) :- st_state(F).
program_fluent_instance(P, F) :- p_initial_state(P, L), member(F, L).
program_fluent_instance(P, F) :- plan_goals(P, L), member(F, L).
program_fluent_instance(P, F) :- p_d_pre(P, Conds), member(holds(F0, _), Conds), unneg(F0, F).
program_fluent_instance(P, F) :- p_initiated(P, _, F, _).
program_fluent_instance(P, F) :- p_terminated(P, _, F, _).

unneg(not(F), F) :- !.
unneg(F, F).

%	Whatever the causal law left unbound falls back to the values seen in
%	the same argument position of the action across the program's denials.
bind_remaining(P, A) :-
	term_variables(A, Vs),
	(   Vs == [] -> true
	;   functor(A, F, N),
	    findall(V, ( p_d_pre(P, Conds), member(happens(A2, _, _), Conds),
			 functor(A2, F, N), arg(_, A2, V), atomic(V) ), Vs0),
	    sort(Vs0, Universe),
	    Universe \== [],
	    bind_all(Vs, Universe)
	).

bind_all([], _).
bind_all([V|Vs], Consts) :- member(V, Consts), bind_all(Vs, Consts).

%	An action with no effect on the state cannot contribute to reaching a
%	goal, so it is dropped before subsets are formed. This is the pruning
%	that keeps subset branching tractable; it can only remove no-ops.
changes_state(P, A) :-
	st_state_list(S),
	apply_actions(P, S, [A], Next),
	\+ same_state(S, Next).

same_state(A, B) :- msort(A, X), msort(B, Y), X == Y.

/* Conditions are evaluated as a *conjunction*, with bindings shared across
   literals. That is not a detail: in

     false loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T, row(_,_) to T.

   the whole constraint is that the three fluents talk about the *same* L.
   Checking each literal independently — which is what forall/2 does — makes
   the denial vacuous, because `not loc(farmer,L)` succeeds for an unbound L
   whenever the farmer is anywhere at all. The engine's holds_all/1 is the
   same conjunctive evaluation the cycle uses, so planner and cycle agree.
*/
conditions_hold(Conds) :-
	exclude([happens(_, _, _)]>>true, Conds, Rest),
	st_now(T),
	bind_condition_times(Rest, T),
	holds_all(Rest).

bind_condition_times([], _).
bind_condition_times([holds(_, T)|Cs], Now) :- !,
	( var(T) -> T = Now ; true ),
	bind_condition_times(Cs, Now).
bind_condition_times([_|Cs], Now) :- bind_condition_times(Cs, Now).

%!	blocked_now(+Action, +Denials) is semidet.
%
%	Row 2: an applicability denial forbids this action in this state.
blocked_now(A, Denials) :-
	member(denial(applicability(Template), Conds), Denials),
	\+ Template \= A,
	copy_term(Template-Conds, T1-C1),
	T1 = A,
	bind_action_literal(C1, A),
	conditions_hold(C1), !.

bind_action_literal(Conds, A) :-
	member(happens(A1, _, _), Conds),
	\+ A1 \= A,
	A1 = A, !.
bind_action_literal(_, _).

%	Row 1: an action-only denial forbids a *set*, not an action.
interferes(Set, Denials) :-
	member(denial(interference, Conds), Denials),
	copy_term(Conds, C),
	findall(A, member(happens(A, _, _), C), Actions0),
	Actions0 \== [],
	split_negated(Actions0, Positive, Negative),
	subsumes_set(Positive, Set),
	%  A negated action literal in a denial says the action must *not* occur
	%  in the same set. `false transport(_,L1,L2) from T1 to T2, not row(L1,L2)
	%  from T1 to T2` is how the declarative goat says a crossing needs a
	%  rowing to go with it — the constraint is on the set, not on either
	%  action alone, which is why it lands here rather than in applicability.
	forall(member(N, Negative), \+ ( member(A, Set), \+ N \= A )),
	conditions_hold(C).

split_negated([], [], []).
split_negated([not(A)|As], P, [A|N]) :- !, split_negated(As, P, N).
split_negated([A|As], [A|P], N) :- split_negated(As, P, N).

subsumes_set([], _).
subsumes_set([A|As], Set) :- member(A, Set), subsumes_set(As, Set).

%	Row 3: prospective denials talk about the state the set would produce,
%	so they are checked against the successor rather than the current state.
prospectively_rejected(_P, Set, Next, Denials) :-
	member(denial(prospective, Conds), Denials),
	copy_term(Conds, C),
	action_literals_match(C, Set),
	with_state(Next, conditions_hold(C)), !.

action_literals_match(Conds, Set) :-
	findall(A, member(happens(A, _, _), Conds), Actions0),
	split_negated(Actions0, Positive, Negative),
	(   Positive == []
	->  true
	;   subsumes_set(Positive, Set)
	),
	forall(member(N, Negative), \+ ( member(A, Set), \+ N \= A )).

		 /*******************************
		 *	  action theory		*
		 *******************************/

%!	apply_actions(+Program, +State, +Set, -Next) is det.
%
%	The successor state, using exactly the causal laws the cycle uses. The
%	state is an ordered list, and the order is preserved for the same reason
%	the cycle preserves it (lps_store.pl's header): solution order is
%	observable.
apply_actions(P, State, Set, Next) :-
	with_state(State, effects_of(P, Set, Terminated, Initiated, Updated)),
	foldl(remove_fluent, Terminated, State, S1),
	foldl([TFl-_, In, Out]>>remove_fluent(TFl, In, Out), Updated, S1, S2),
	foldl(add_fluent, Initiated, S2, S3),
	foldl([_-IFl, In, Out]>>add_fluent(IFl, In, Out), Updated, S3, Next).

effects_of(P, Set, Terminated, Initiated, Updated) :-
	st_now(T), T2 is T + 1,
	findall(Fl, ( member(A, Set), p_terminated(P, happens(A, T, T2), Fl, Cond),
		      holds_all(Cond) ), Terminated),
	findall(Fl, ( member(A, Set), p_initiated(P, happens(A, T, T2), Fl, Cond),
		      holds_all(Cond) ), Initiated),
	findall(TFl-IFl, ( member(A, Set), p_updated(P, happens(A, T, T2), TFl, Old-New, Cond),
			   replace_term(TFl, Old, New, IFl), st_state(TFl),
			   holds_all(Cond) ), Updated).

remove_fluent(F, In, Out) :- exclude_unif(F, In, Out).
add_fluent(F, In, Out) :- ( memberchk_eq(F, In) -> Out = In ; append(In, [F], Out) ).

memberchk_eq(X, [Y|_]) :- X == Y, !.
memberchk_eq(X, [_|T]) :- memberchk_eq(X, T).

exclude_unif(_, [], []).
exclude_unif(Pat, [X|Xs], Ys) :-
	( \+ Pat \= X -> Ys = Ys1 ; Ys = [X|Ys1] ),
	exclude_unif(Pat, Xs, Ys1).

		 /*******************************
		 *    handing the plan over	*
		 *******************************/

%!	plan_to_session_goals(+Plan, +StartTime, +Options, -Goals) is det.
%
%	§I.7.5: the plan is handed to the *ordinary* cycle as goals with pinned
%	times, one action set per cycle. Nothing else changes — preconditions,
%	integrity constraints and the trace all work exactly as they do for a
%	hand-written program, which is why a planned program's `.lpst` is an
%	ordinary `.lpst`.
plan_to_session_goals(Plan, StartTime, _Options, Goals) :-
	findall(goal(Id, non_discardable, _, [], [], [Discard], (Conj, Discard = yes)),
		( nth0(I, Plan, Set), Set \== [],
		  T is StartTime + I, T2 is T + 1,
		  step_conjunction(Set, T, T2, Conj),
		  Id is 1000000 + I ),
		Goals).

step_conjunction(Set, T1, T2, Conj) :-
	findall(happens(A, T1, T2), member(A, Set), Literals),
	Conj = Literals.
