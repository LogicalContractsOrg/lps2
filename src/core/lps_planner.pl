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
%	Plan is a list of action sets, one per cycle.
%
%	Two searches (§I.7.4 stages 1 and 2), chosen by the `search/1` option:
%
%	  * `bfs` — breadth-first. Complete and **optimal in plan length**, and
%	    hopeless past a dozen steps: the frontier is b^d.
%	  * `greedy` — greedy best-first on the delete-relaxation heuristic
%	    below. Not optimal, occasionally a few steps long, and the only one
%	    of the two that finishes on a problem like `examples/blocks.lps`.
%	  * `auto` (the default) — BFS under a node budget, then greedy if the
%	    budget runs out. Optimal where optimality is affordable.
%
%	`nodes(N)` sets the budget; `search(bfs)` and `search(greedy)` are
%	unbudgeted.
plan_for(P, Goals, Options, Plan) :-
	horizon(Options, Horizon),
	st_state_list(State0),
	classify_denials(P, Denials),
	save_store_state(Saved),
	max_concurrency(Options, MaxC),
	Cfg = cfg(Horizon, MaxC),
	setup_call_cleanup(
	    true,
	    search_with(Options, P, State0, Goals, Denials, Cfg, Plan),
	    restore_store_state(Saved)).

		 /*******************************
		 *    choosing a search		*
		 *******************************/

/* The `auto` rule, and it is deliberately something you can hold in your head:

     try BFS with a node budget; if the budget runs out, hand over to greedy.

   No static measurement of the problem can tell these two cases apart —
   I tried. Branching factor does not: the goat branches four ways at the
   start and so does blocks world. The heuristic's own estimate at the initial
   state does not either, and for a very specific reason: the delete relaxation
   makes blocks world *look* four steps deep, because in a world where moving a
   block never un-clears anything you can build the tower directly. That is
   exactly the illusion that makes the heuristic a good guide and a bad
   estimator.

   So auto measures the only thing that is not guesswork — how far BFS
   actually gets. A couple of hundred expansions settles the goat (it needs
   fewer than a hundred) and is cheap enough to throw away on a problem where
   BFS was never going to finish. `nodes(N)` moves the line.
   Programs that want a guarantee ask for it: `search(bfs)` is unbudgeted and
   optimal, which is why examples/goat_declarative.pl pins it.
*/
search_with(Options, P, State0, Goals, Denials, Cfg, Plan) :-
	strategy(Options, S0),
	budget(Options, Budget),
	(   S0 == auto
	->  (   run_search(bfs, P, State0, Goals, Denials, Cfg, Budget, Plan)
	    ->	record_strategy(bfs, within_budget(Budget))
	    ;	run_search(greedy, P, State0, Goals, Denials, Cfg, infinite, Plan),
		record_strategy(greedy, after_budget(Budget))
	    )
	;   run_search(S0, P, State0, Goals, Denials, Cfg, infinite, Plan),
	    record_strategy(S0, declared)
	).

strategy(Options, S) :- memberchk(search(S), Options), search_name(S), !.
strategy(_, auto).

search_name(bfs).
search_name(greedy).
search_name(auto).

%	Expansions, not states: the number of times a node is taken off the
%	frontier and its successors computed. Successor generation is where the
%	time goes, so it is the honest unit.
budget(Options, B) :- memberchk(nodes(B), Options), integer(B), !.
budget(_, 250).

run_search(bfs, P, State0, Goals, Denials, Cfg, Budget, Plan) :-
	bfs([node(State0, [])], [State0], P, Goals, Denials, Cfg, Budget, Plan).
run_search(greedy, P, State0, Goals, Denials, Cfg, Budget, Plan) :-
	( relaxed_h(P, State0, Goals, H0) -> true ; H0 = 0 ),
	greedy([H0-node(State0, [])], [State0], P, Goals, Denials, Cfg, Budget, Plan).

record_strategy(S, How) :- st_trace(plan_strategy(S, How)).

spend(infinite, infinite) :- !.
spend(N, N1) :- N > 0, N1 is N - 1.

horizon(Options, H) :- memberchk(horizon(H), Options), !.
horizon(_, 12).

max_concurrency(Options, N) :- memberchk(max_concurrency(N), Options), !.
max_concurrency(_, 3).

save_store_state(state(S, N)) :- st_state_list(S), st_now(N).
restore_store_state(state(S, N)) :- st_set_state(S), st_set_now(N).

bfs([node(State, Plan0)|_], _Visited, P, Goals, _D, _Cfg, _B, Plan) :-
	with_state(State, goals_hold(P, Goals)), !,
	reverse(Plan0, Plan).
bfs([node(_, Plan0)|Rest], Visited, P, Goals, D, Cfg, B, Plan) :-
	Cfg = cfg(H, _), length(Plan0, L), L >= H, !,
	bfs(Rest, Visited, P, Goals, D, Cfg, B, Plan).
bfs([node(State, Plan0)|Rest], Visited, P, Goals, D, Cfg, B, Plan) :-
	spend(B, B1),
	Cfg = cfg(_, MaxC),
	successors(P, State, D, MaxC, Succs),
	fresh(Succs, Visited, Plan0, New, Visited1),
	append(Rest, New, Queue),
	bfs(Queue, Visited1, P, Goals, D, Cfg, B1, Plan).

fresh([], Visited, _, [], Visited).
fresh([ActionSet-S|Ss], Visited, Plan0, New, Visited1) :-
	msort(S, Key),
	(   member(V, Visited), msort(V, Key)
	->  fresh(Ss, Visited, Plan0, New, Visited1)
	;   New = [node(S, [ActionSet|Plan0])|New1],
	    fresh(Ss, [S|Visited], Plan0, New1, Visited1)
	).

		 /*******************************
		 *   greedy best-first (stage 2)*
		 *******************************/

/* Same successor relation, same denials, same everything — only the order in
   which nodes come off the frontier changes. Open is kept sorted by the
   heuristic, cheapest first; ties keep insertion order, which is
   breadth-first-ish and prefers shorter plans among equally promising states.
*/
greedy([_-node(State, Plan0)|_], _Visited, P, Goals, _D, _Cfg, _B, Plan) :-
	with_state(State, goals_hold(P, Goals)), !,
	reverse(Plan0, Plan).
greedy([_-node(_, Plan0)|Rest], Visited, P, Goals, D, Cfg, B, Plan) :-
	Cfg = cfg(H, _), length(Plan0, L), L >= H, !,
	greedy(Rest, Visited, P, Goals, D, Cfg, B, Plan).
greedy([_-node(State, Plan0)|Rest], Visited, P, Goals, D, Cfg, B, Plan) :-
	spend(B, B1),
	Cfg = cfg(_, MaxC),
	successors(P, State, D, MaxC, Succs),
	fresh(Succs, Visited, Plan0, New, Visited1),
	%  A node the relaxation cannot solve at all is a dead end and is
	%  dropped, not merely deprioritised. That is where most of the pruning
	%  comes from on a problem with irreversible mistakes.
	findall(HN-N,
		( member(N, New), N = node(S, _), relaxed_h(P, S, Goals, HN) ),
		Scored),
	append(Rest, Scored, Open0),
	keysort(Open0, Open),
	greedy(Open, Visited1, P, Goals, D, Cfg, B1, Plan).

/* The heuristic: h^add over the delete relaxation (§I.7.4 stage 2).

   Build the relaxed planning graph — apply every applicable action, keep only
   what it *adds*, never remove anything — until each goal has appeared or the
   layers stop growing. h is the sum over goals of the layer at which each first
   appeared. Ignoring deletions makes it cheap and makes it lie in a known
   direction (it never notices that achieving one goal undid another), which is
   why it guides a greedy search well and would ruin an optimal one.

   The failure case matters as much as the number: if the layers reach a
   fixpoint with a goal still missing, then *no* sequence of actions can reach
   it even when nothing is ever undone. The state is a genuine dead end, and
   relaxed_h/4 fails rather than returning a large number.
*/
relaxed_h(P, State, Goals, H) :-
	goal_list(Goals, Gs),
	relaxed_layers(P, State, Gs, 0, [], Costs),
	length(Gs, NG), length(Costs, NC), NC =:= NG,
	sum_list(Costs, H).

goal_list(Goals, Gs) :- is_list(Goals), !, Gs = Goals.
goal_list((A, B), Gs) :- !, goal_list(A, GA), goal_list(B, GB), append(GA, GB, Gs).
goal_list(G, [G]).

%	Costs0 accumulates Goal-Layer for goals already reached; the recursion
%	stops when every goal has one, or when a layer adds nothing.
relaxed_layers(P, Layer, Gs, N, Costs0, Costs) :-
	reached_now(P, Layer, Gs, N, Costs0, Costs1),
	length(Costs1, Reached), length(Gs, NG),
	(   Reached =:= NG
	->  pairs_costs(Costs1, Costs)
	;   N >= 40                      % a guard, not a policy: 40 layers is a
	->  fail                         % relaxation that is going nowhere
	;   relaxed_expand(P, Layer, Next),
	    \+ same_state(Layer, Next),
	    N1 is N + 1,
	    relaxed_layers(P, Next, Gs, N1, Costs1, Costs)
	).

pairs_costs(Pairs, Costs) :- findall(C, member(_-C, Pairs), Costs).

reached_now(_, _, [], _, Costs, Costs) :- !.
reached_now(P, Layer, [G|Gs], N, Costs0, Costs) :-
	(   member(G0-_, Costs0), G0 == G
	->  Costs1 = Costs0
	;   with_state(Layer, goals_hold(P, [G]))
	->  Costs1 = [G-N|Costs0]
	;   Costs1 = Costs0
	),
	reached_now(P, Layer, Gs, N, Costs1, Costs).

%	One relaxed layer: everything every applicable action adds, unioned onto
%	what is already there. Terminations and the removal half of `updates` are
%	dropped — that is the relaxation.
relaxed_expand(P, Layer, Next) :-
	with_state(Layer, relaxed_additions(P, Adds)),
	foldl(add_fluent, Adds, Layer, Next).

relaxed_additions(P, Adds) :-
	findall(A, ( candidate_action(P, A), ground(A) ), As0),
	sort(As0, As),
	st_now(T), T2 is T + 1,
	findall(Fl,
		( member(A, As),
		  (   p_initiated(P, happens(A, T, T2), Fl, Cond), holds_all(Cond)
		  ;   p_updated(P, happens(A, T, T2), TFl, Old-New, Cond),
		      st_state(TFl), holds_all(Cond),
		      replace_term(TFl, Old, New, Fl)
		  ) ),
		Adds0),
	sort(Adds0, Adds).

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

%!	successors(+Program, +State, +Denials, +MaxConcurrency, -Pairs) is det.
%
%	Pairs are ActionSet-NextState. An action set must be individually
%	applicable, jointly free of interference, and must not produce a state
%	that a prospective denial rejects.
successors(P, State, Denials, MaxC, Pairs) :-
	with_state(State, applicable_actions(P, Denials, Applicable)),
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
/* A law whose new value is *computed* — `chop(tree) updates N to M in
   has(log, N) if M is N + 1` — has already bound New by the time the
   conditions have been solved, and there is nothing to enumerate. Consulting
   the position universe anyway asks whether the computed value happens to
   appear somewhere in the program text, which for arithmetic it usually does
   not: the planner then generated no candidate actions at all and reported
   that a perfectly ordinary crafting problem had no plan.
*/
bind_replacements(_, _, _, New) :-
	ground(New), !.
bind_replacements(P, TFl, Old, New) :-
	is_list(Old), !,
	bind_replacement_list(P, TFl, Old, New).
bind_replacements(P, TFl, Old, New) :-
	position_universe(P, TFl, Old, Values),
	member(New, Values).

bind_replacement_list(_, _, [], []).
bind_replacement_list(P, TFl, [O|Os], [N|Ns]) :-
	(   ground(N)
	->  true
	;   position_universe(P, TFl, O, Values),
	    member(N, Values)
	),
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

/* Whatever the causal law left unbound has to come from somewhere else, and
   the *preconditions* are where. `pick-up(?x)` in blocks world binds nothing
   through its effect — `holding(?x)` is created, not matched — so an engine
   that generates only from effects generates nothing at all, which is what
   happened the first time a PDDL domain came through this planner.

   Its applicability denials say what must hold for it to run:

       false pick_up(X) from T1 to _, not clear(X) at T1.
       false pick_up(X) from T1 to _, not ontable(X) at T1.

   so `clear(X)` and `ontable(X)` are requirements, and solving them against
   the current state binds X to blocks that are actually clear and on the
   table. This is the standard "generate from preconditions" move, and it is
   what makes the planner usable on domains written by someone else.
*/
bind_remaining(P, A) :-
	term_variables(A, Vs),
	(   Vs == [] -> true
	%  The test is on a *copy*, because `->` commits to its condition's
	%  first solution — asking "can requirements bind this?" by trying to
	%  bind it yields exactly one candidate action instead of all of them.
	;   can_bind_from_requirements(P, A)
	->  bind_from_requirements(P, A)
	;   functor(A, F, N),
	    findall(V, ( p_d_pre(P, Conds), member(happens(A2, _, _), Conds),
			 functor(A2, F, N), arg(_, A2, V), atomic(V) ), Vs0),
	    sort(Vs0, Universe),
	    Universe \== [],
	    bind_all(Vs, Universe)
	).

can_bind_from_requirements(P, A) :-
	copy_term(A, A1),
	denial_requirement(P, A1, R),
	satisfy_requirement(P, R), !.

bind_from_requirements(P, A) :-
	term_variables(A, Vs0), length(Vs0, N0), N0 > 0,
	denial_requirement(P, A, R),
	satisfy_requirement(P, R),
	term_variables(A, Vs1), length(Vs1, N1),
	N1 < N0,                                  % this step bound something
	( N1 =:= 0 -> true ; bind_from_requirements(P, A) ).

/* One positive requirement of an applicability denial, with its variables
   shared with this action. The copy is deliberate: the denial's own variables
   must not be bound for later candidates.

   Two shapes, because a requirement can be about the state or about the
   program: `holds(not(F), T)` says the fluent F must hold, and a bare `not(G)`
   says the timeless goal G must succeed — which is how a PDDL type test
   (`(room ?from)`) arrives.
*/
denial_requirement(P, A, Req) :-
	p_d_pre(P, Conds0),
	copy_term(Conds0, Conds),
	member(happens(A2, _, _), Conds),
	\+ A2 \= A,
	A2 = A,
	member(C, Conds),
	requirement_of(C, Req).

requirement_of(holds(not(F), _), state(F)) :- nonvar(F).
requirement_of(not(G), goal(G)) :- nonvar(G), G \= holds(_, _), G \= happens(_, _, _).

satisfy_requirement(_, state(F)) :- st_state(F).
%	A timeless requirement is answered by the program's own timeless clauses
%	first — they are indexed, not asserted, so a module call does not see
%	them — and by the module only as a fallback for genuine externals.
satisfy_requirement(P, goal(G)) :-
	(   p_l_timeless(P, G, Body), holds_all(Body)
	;   catch(p_call(P, G), _, fail)
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
		  record_plan_step(T, I, Set),
		  Id is 1000000 + I ),
		Goals).

/* A planned action has no reactive rule behind it and no composite-event
   ancestry, so §I.10.5's chain — action → goal path → rule instance — bottoms
   out immediately and the explanation says nothing. The plan *is* the
   provenance here, so it is recorded: which step of which `achieve` scheduled
   this action, for which cycle. "Why did A not happen at T?" then has a real
   answer under planning mode too — usually "because the plan schedules it for
   a different cycle".
*/
record_plan_step(Cycle, Index, Set) :-
	st_program(P),
	( plan_goals(P, Achieve) -> true ; Achieve = [] ),
	copy_term(Set-Achieve, S-A), numbervars(S-A, 0, _),
	st_trace(plan_step(Cycle, Index, S, A)).

step_conjunction(Set, T1, T2, Conj) :-
	findall(happens(A, T1, T2), member(A, Set), Literals),
	Conj = Literals.
