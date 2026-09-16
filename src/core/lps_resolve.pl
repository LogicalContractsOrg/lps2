/* lps_resolve.pl — the `dc` resolution strategy (§I.5.3).

   This is where trace fidelity is won or lost. Everything here is written
   against docs/dev/semantics/selection-spec.md rather than against a reading of the old
   code's accidents; the SP numbers in the comments are that document's.

   Two mutually recursive machines:

   `resolve_until_action/4` walks one goal until it hits something that cannot
   be decided here and now — a literal whose time has not arrived, a literal
   with several possible reductions, an if-then-else, a parallelisable
   conjunction. It then *suspends*, returning a Ball naming the reason and a
   Continuation naming the rest of the goal. A bound Ball means suspension; an
   unbound one means the goal ran to completion. (Upstream's name for this
   predicate is misleading: it also stops on alternatives, not just actions.)

   `dc_resolve_goals/2` is the scheduler. It walks the goal list head-first
   (SP6), turns each suspension into new goals, and decides what a failure
   means: a goal that fails takes the whole cycle down with it unless a
   sibling alternative is still alive (SP11).

   The bookkeeping that looks gratuitous is not. Each goal carries

	goal(Id, Discard, MyFailure, OurFailures, SharedVars, Ancestors, G)

   where Discard/MyFailure/OurFailures are *unbound variables shared between
   sibling alternatives*. Binding one is how a succeeding branch tells its
   siblings to stop (SP9), and how a failing branch tells its parent whether
   anything is left to try. Reproducing that wiring is what makes disjunctive
   goals commit to the same alternative the 2021 engine did.
*/

:- module(lps_resolve, [
	resolve_until_action/4,  % +Goal, +Ancestors, -Ball, -Continuation
	dc_resolve_goals/2,      % +Goals, -NewGoals
	dc_process/5,            % +Rules, +AccR, -NewRules, +AccG, -NewGoals
	split_goals_and_events/3,
	has_no_future/3
	]).

:- use_module(lps_ops).
:- use_module(library(lists)).
:- use_module(library(apply), [foldl/4]).
:- use_module(library(assoc)).
:- use_module(library(terms), [variant/2]).
:- use_module(lps_store).
:- use_module(lps_program).
:- use_module(lps_terms).
:- use_module(lps_time).
:- use_module(lps_query).

:- multifile prolog:message//1.
prolog:message(lps_rua(G, _A)) --> ['rua: ~p'-[G]].

		 /*******************************
		 *    resolve_until_action/4	*
		 *******************************/

%	Upstream's `option(debug)` hook, kept: it is the only practical way to
%	see why a goal took the branch it took. Writes nothing unless asked.
resolve_until_action(V, A, _, _) :-
	st_option(debug), format(user_error, 'rua: ~p~n', [V]), ignore(A=A), fail.
resolve_until_action(V, _, _, _) :-
	var(V), !, throw(error(lps_var_goal, _)).
resolve_until_action(true, _, _, true) :- !.
resolve_until_action([], _, _, true) :- !.
resolve_until_action(G, Ancestors, B, C) :-
	is_list(G), parallelizable_conjunction(G, Branches, Gn), !,
	B = conjunction(Branches, Gn, Ancestors), C = true.
resolve_until_action(lps_conjunction_control(OurSuccesses), _, _, C) :-
	ground(OurSuccesses), !, C = true.
resolve_until_action(lps_conjunction_control(_), _, Ball, Cont) :- !,
	Ball = conjunction_prunning,
	Cont = throw(error(lps_inconsistent_conjunction_prunning, _)).
resolve_until_action([G1|Gn], A, B, C) :- !,
	resolve_until_action(G1, A, B, C1),
	check_ball(B, C1, G1),
	(   var(B)
	->  resolve_until_action(Gn, A, B, C)
	;   simplify_conjunction(C1, Gn, C)
	).
resolve_until_action((G1, Gn), A, B, C) :- !,
	resolve_until_action(G1, A, B, C1),
	check_ball(B, C1, G1),
	(   var(B)
	->  resolve_until_action(Gn, A, B, C)
	;   simplify_conjunction(C1, Gn, C)
	).
resolve_until_action((Cond -> Then ; Else), Ancestors, Ball, Continuation) :- !,
	Ball = ite(Ancestors, Cond, Then, Else), Continuation = true.
resolve_until_action('$_wait'(Guard), A, Ball, Continuation) :- !,
	(   call(Guard)
	->  Continuation = true
	;   Ball = later('$_wait'(Guard), A), Continuation = '$_wait'(Guard)
	).

% ----- fluents -----
resolve_until_action(G, Ancestors, Ball, Cont) :-
	premature_real_time_fluent(G), !,
	Ball = later(G, Ancestors), Cont = G.
resolve_until_action(G, Ancestors, Ball, Cont) :-
	G = holds(_F, _T), real_time_literal(G, Goals), !,
	resolve_until_action(Goals, Ancestors, Ball, Cont).
resolve_until_action(G, Ancestors, Ball, Cont) :-
	G = holds(_F, T_),
	ground(T_), expression_to_time(T_, T), st_now(Now), T > Now, !,
	Ball = later(G, Ancestors), Cont = G.
resolve_until_action(holds(F, T), _A, _, true) :-
	st_option(no_parallel), dc_query(holds(F, T)).
resolve_until_action(Fluent, Ancestors, B, C) :-
	\+ st_option(no_parallel),
	Fluent = holds(Pred, T),
	st_program(P), p_intensional(P, Pred),
	Pred \= real_date(_),
	!,
	%  Spawn one goal per alternative definition (SP10). Delaying of
	%  intensional fluents is dispensed with by requiring the head time to
	%  be a free variable; a timeless body gets an extra holds(true,T) so it
	%  still has something to delay on.
	findall(l_int(Fluent, Body),
		( p_l_int(P, Fluent, Body_),
		  (   a_literal(Body_, holds(_, _))
		  ->  Body = Body_
		  ;   Body = (holds(true, T), Body_)
		  ) ),
		Alternatives),
	Alternatives \= [],
	(   Alternatives = [l_int(Fluent, Body)]
	->  resolve_until_action(Body, Ancestors, B, C)
	;   B = l_ints_disjunction(l_int(Fluent, Body), Alternatives, Ancestors), C = true
	).
resolve_until_action(Fl, Ancestors, B, C) :-
	Fl = holds(real_date(_), T),
	\+ st_option(no_parallel),
	findall(Fl, dc_query(Fl), Answers), Answers \= [],
	C = true,
	(   ( ground(T), Answers = [Fl] )
	->  true
	;   B = disjunction(Fl, Answers, Ancestors)
	).
resolve_until_action(holds(F, T), Ancestors, B, C) :-
	\+ st_option(no_parallel),
	findall(holds(F, T), dc_query(holds(F, T)), Answers), Answers \= [],
	(   ( ground(T), Answers = [holds(F, T)] )
	->  C = true
	;   B = disjunction(holds(F, T), Answers, Ancestors), C = true
	).
resolve_until_action(holds(F, T), Ancestors, Ball, Cont) :- !,
	\+ ground(T),
	Ball = later(holds(F, T), Ancestors), Cont = holds(F, T).

% ----- events and actions -----
resolve_until_action(happens(E, T1, T2), A, B, C) :-
	st_option(no_parallel),
	st_program(P), p_macroaction(P, E),
	!,
	p_l_events(P, happens(E, T1, T2), Body),
	resolve_until_action(Body, [happens(E, T1, T2)|A], B, C).
resolve_until_action(G, _Ancestors, _Ball, _Cont) :-
	outdated_real_time_event(G), !, fail.
resolve_until_action(G, Ancestors, Ball, Cont) :-
	G = happens(_, _, _), real_time_literal(G, Goals), !,
	resolve_until_action(Goals, Ancestors, Ball, Cont).
resolve_until_action(happens(_E, T1_, T2_), _A, _, _) :-
	%  outdated as per cycle time: fail
	st_now(Now),
	(   expression_to_time(T1_, T1), ground(T1), T1 < Now
	;   expression_to_time(T2_, T2), ground(T2), T2 < Now + 1
	),
	!, fail.
resolve_until_action(happens(E, T1_, T2_), A, Ball, Cont) :-
	%  premature: delay
	st_now(Now),
	st_program(P),
	(   ground(T1_), expression_to_time(T1_, T1), T1 > Now
	;   ground(T2_), expression_to_time(T2_, T2), T2 > Now + 1, \+ p_macroaction(P, E)
	;   premature_system_action(E)
	),
	!,
	Ball = later(happens(E, T1_, T2_), A), Cont = happens(E, T1_, T2_).
resolve_until_action(happens(E, T1_, T2_), A, B, C) :-
	st_program(P), p_macroaction(P, E), !,
	%  general case: spawn disjunctive goals, one per l_events clause (SP9)
	expression_to_time(T1_, T1), expression_to_time(T2_, T2),
	findall(l_events(happens(E, T1, T2), Body),
		( p_l_events(P, happens(E, T1, T2), Body_),
		  (   ( T1 \== T2, nonvar(T2) )
		  ->  Body = (Body_, holds(true, T), T =< T2 - 1)
		  ;   lps_contains_var(T2, Body_)
		  ->  Body = Body_
		  ;   Body = (Body_, holds(true, T2))
		  ) ),
		Alternatives),
	Alternatives \= [],
	(   Alternatives = [l_events(happens(E, T1, T2), Body)]
	->  resolve_until_action(Body, [happens(E, T1, T2)|A], B, C)
	;   B = l_events_disjunction(l_events(happens(E, T1, T2), Body), Alternatives, A),
	    C = true
	).
resolve_until_action(happens(E, T1_, T2_), _Ancestors, _B, true) :-
	%  an event that already occurred. Deliberately NOT given the
	%  disjunction treatment above: doing so breaks
	%  SzaboLanguage_insurance_irrelevant_events.pl (selection_spec SP10).
	expression_to_time(T1_, T1), st_now(T1),
	expression_to_time(T2_, T2), T2 is T1 + 1,
	(   ( nonvar(E), E = not(RealE) )
	->  \+ st_happens(RealE, T1, T2)
	;   st_happens(E, T1, T2)
	).
resolve_until_action(happens(E, T1_, T2_), A, Ball, Cont) :-
	st_option(more_actions),
	expression_to_time(T1_, T1), expression_to_time(T2_, T2),
	\+ ground(T1), \+ ground(T2),
	!,
	resolve_until_action((holds(true, T1), happens(E, T1, T2)), A, Ball, Cont).
resolve_until_action(happens(E, T1_, T2_), A, _, Cont) :-
	%  select and execute a system action
	expression_to_time(T1_, T1), st_now(T1),
	expression_to_time(T2_, T2),
	\+ ( nonvar(E), E = not(_) ),
	\+ st_happens(E, T1, T2),
	st_program(P), p_system_action(P, E),
	\+ functor(E, lps_terminate, _),
	!,
	Cont = true,
	T2 is T1 + 1,
	record_action_ancestors(E, A),
	findall(E, p_call(P, E), Solutions),
	Solutions \= [],
	%  Iterate *without* backtracking: the event set is a backtrackable
	%  global, so a failure-driven loop would undo each addition as it went.
	add_happens_all(Solutions, T1, T2),
	st_happens(E, T1, T2).

resolve_until_action(happens(E, T1_, T2_), A, _, true) :-
	%  SP8 — select an action: commit immediately, then reject it if a
	%  current-state denial holds. The store is backtrackable, so an action
	%  committed here is undone automatically if resolution later fails,
	%  which is exactly upstream's retract-on-backtracking.
	%
	%  One deliberate difference: upstream's `\+ system_action(E)` guard on
	%  the undo leaves a *system* action asserted across a backtrack. The
	%  only system action that can reach this clause is lps_terminate — every
	%  other one is caught by the clause above — and it ends the run in the
	%  next cycle regardless, so the difference is unobservable. Reproducing
	%  it would mean a second, non-backtrackable event store for one case.
	expression_to_time(T1_, T1), st_now(T1),
	expression_to_time(T2_, T2),
	\+ ( nonvar(E), E = not(_) ),
	\+ st_happens(E, T1, T2),
	T2 is T1 + 1,
	st_program(P),
	p_action(P, E),
	( p_event(P, E) -> ground(E) ; true ),
	record_action_ancestors(E, A),
	st_add_happens(happens(E, T1, T2)),
	(   ( p_d_pre(P, current, Conds), holds_all(Conds, T1, T2) )
	->  record_action_blocked(E, T1, T2, Conds),
	    st_del_happens(happens(E, T1, T2)), fail
	;   true
	).
resolve_until_action(happens(E, T1_, T2_), A, Ball, Cont) :- !,
	Ball = later(happens(E, T1, T2), A), Cont = happens(E, T1, T2),
	expression_to_time(T1_, T1), expression_to_time(T2_, T2),
	\+ ground(T1), \+ ground(T2),
	(   ( nonvar(E), E = not(RealE) )
	->  \+ \+ st_happens(RealE, T1, T2)
	;   \+ st_happens(E, T1, T2)
	).

% ----- mixed time comparisons, timeless goals -----
resolve_until_action(G, A, Ball, Cont) :-
	mixed_time_comparison(G, NewG), !,
	resolve_until_action(NewG, A, Ball, Cont).
resolve_until_action(tc(G), _A, _, Cont) :-
	ground(G), !, call(G), Cont = true.
resolve_until_action(tc(G), A, Ball, Cont) :- !,
	Ball = later(tc(G), A), Cont = tc(G).
resolve_until_action(G, _A, _, true) :-
	st_option(no_parallel), !,
	st_program(P),
	(   \+ p_timeless(P, G)
	->  p_call(P, G)
	;   ( p_l_timeless(P, G, Body), evaluate(Body) ; p_timeless_fact(P, G) )
	).
resolve_until_action(G, _Ancestors, _B, true) :-
	( G = (not G_) ; G = (\+ G_) ), !,
	st_program(P),
	(   (   \+ p_timeless(P, G_)
	    ->	p_call(P, G_)
	    ;	( p_l_timeless(P, G_, Body), evaluate(Body) ; p_timeless_fact(P, G_) )
	    )
	->  fail
	;   true
	).
resolve_until_action(G, Ancestors, B, true) :-
	st_program(P),
	findall(G,
		(   \+ p_timeless(P, G)
		->  p_call(P, G)
		;   ( p_l_timeless(P, G, Body), evaluate(Body) ; p_timeless_fact(P, G) )
		),
		Answers),
	Answers \= [],
	(   Answers = [G]
	->  true
	;   B = disjunction(G, Answers, Ancestors)
	).

add_happens_all([], _, _).
add_happens_all([S|Ss], T1, T2) :-
	st_add_happens(happens(S, T1, T2)),
	add_happens_all(Ss, T1, T2).

check_ball(B, C1, G1) :-
	(   ( var(B), C1 \== true )
	->  throw(error(lps_inconsistent_ball(G1, C1), _))
	;   true
	).

%!	parallelizable_conjunction(+Goals, -Branches, -Continuation) is semidet.
%
%	A prefix of two or more macro-actions all starting at the same time can
%	be pursued in parallel.
parallelizable_conjunction([happens(E, T1, T2)|Gn], [happens(E, T1, T2)|Branches], Continuation) :-
	st_program(P), p_macroaction(P, E),
	parallelizable_conjunction(Gn, T1, Branches, Continuation),
	Branches = [_|_].

parallelizable_conjunction([happens(E, T1, T2)|Gn], T1_, [happens(E, T1, T2)|Branches], Continuation) :-
	T1_ == T1, st_program(P), p_macroaction(P, E), !,
	parallelizable_conjunction(Gn, T1, Branches, Continuation).
parallelizable_conjunction(G, _, [], G).

%	No blocking system actions in a pure core; the hook stays for edges.
premature_system_action(_) :- fail.

premature_real_time_fluent(holds(_, T)) :-
	ground(T), T = _Y/_M/_D,
	get_the_real_date(Today), T @> Today.

outdated_real_time_event(happens(_, T1, T2)) :-
	get_the_real_date(Now),
	(   nonvar(T2), T2 = _/_/_, Now @> T2
	;   nonvar(T1), T1 = _/_/_, Now @> T1
	).

get_the_real_date(Today) :- dc_query(holds(real_date(Today), _)).

/* §I.10.5: action ancestry is recorded unconditionally and is a first-class
   trace record, not a by-product of make_test that gets thrown away. The
   chain — committed action → composite events that produced it → the rule
   instance behind them — is what "why did A happen?" answers with.

   One deliberate departure: upstream keeps the record set deduplicated by
   variant against *everything ever recorded*, which is a linear scan per
   committed action and quadratic over a long run. Since the records are
   explicitly not part of the test contract (§0.2), deduplication is left to
   the reader; the engine records the chain and tags it with the cycle.
   Records made for an action that is later backtracked away disappear with
   it, because the trace lives in the backtrackable store.
*/
%	The action is carried so that the forest is per-action: §I.10.5 wants
%	"each committed action → the goal-tree path that produced it", and a
%	cycle-wide pool of ancestors cannot say which path belongs to which
%	action when two are committed in the same cycle — which is the normal
%	case, since LPS cycles allow several actions at once.
record_action_ancestors(A, Ancestors) :-
	st_now(Cycle),
	record_ancestors_(Ancestors, Cycle, A).

record_ancestors_([_], _, _) :- !.      % last element is the discarder, not a call
record_ancestors_([happens(E, T1, T2)|As], Cycle, A) :- !,
	st_ancestor(action_ancestor(Cycle, A, E, T1, T2)),
	record_ancestors_(As, Cycle, A).
record_ancestors_([], _, _).

/* §I.10.5's derivation forest needs two more links than ancestry alone gives.

   `rule_fired` names the reactive-rule instance that created a goal, which is
   the top of the chain "committed action → goal path → rule instance →
   the observation or state change that fired the antecedent". The consequent
   is recorded rather than a rule index because by the time the antecedent has
   emptied — which is when the goal is created — the rule has been rewritten
   past recognition. lps_explain.pl matches the consequent back against the
   program's rules and reports honestly when that is ambiguous.

   `action_blocked` is the second of the four answerable cases for "why did A
   not happen?": the goal existed, but a denial blocked the action. It is
   recorded non-backtrackably, because the block really did happen even if a
   different branch later succeeded — with the caveat, documented rather than
   hidden, that a branch later abandoned can leave a record behind.
*/
record_rule_fired(Id, Consequent) :-
	st_now(Cycle),
	copy_term(Consequent, C), numbervars(C, 0, _),
	st_trace_once(rule_fired(Cycle, Id, C)).

record_action_blocked(E, T1, T2, Denial) :-
	st_now(Cycle),
	copy_term(E-Denial, E1-D1), numbervars(E1-D1, 0, _),
	st_trace_once(action_blocked(Cycle, E1, T1, T2, D1)).

		 /*******************************
		 *	   future killers	*
		 *******************************/

/* SP12. A goal whose remaining temporal conditions can no longer be satisfied
   is marked failed now rather than carried forward. This changes how many
   cycles run, so it changes cycle alignment — it is not an optimisation.
*/

has_no_future(G, Ancestors, FK) :-
	future_killer(G, Ancestors, FK, T, K),
	nonvar(K),
	(   misc_to_realtime(K, _)
	->  get_the_real_date(T)
	;   st_now(T)
	),
	ground(FK), \+ call(FK).
has_no_future(G, _Ancestors, Lit) :-
	get_the_real_date(Today),
	a_literal(G, Lit),
	(   Lit = holds(real_date(RT), _)
	;   Lit = happens(E, _, _), a_real_time_event(E, RT)
	),
	nonvar(RT), RT = _Year/_Month/_Second,
	Today @> RT.

future_killer(G, Ancestors, FK, T, K) :-
	time_variables(G, Gvars), time_variables(Ancestors, Avars),
	append(Avars, Gvars, Vars),
	a_literal(G, FK_),
	limited_future_expression(FK_, FK, Vars, T, K).

time_variables(G, UniqueVars) :-
	findall(T-G,
		( a_literal(G, L),
		  (   L = holds(_, T)
		  ;   L = happens(_, T, _)
		  ;   L = happens(_, _, T)
		  ;   L = happens(E, _, _), a_real_time_event(E, T)
		  ),
		  \+ ground(T) ),
		Pairs),
	bind_and_extract(Pairs, G, Vars),
	sort(Vars, UniqueVars).

bind_and_extract([T-G|Pairs], G, [T|Vars]) :- !, bind_and_extract(Pairs, G, Vars).
bind_and_extract([], _, []).

%	NOTE the structured-time branches leave K unbound, so has_no_future/3's
%	`nonvar(K)` rejects them and only the cycle-time cases can kill a goal.
%	That is upstream's behaviour; "fixing" it would change how many cycles
%	run, and cycle count is the most observable thing there is.
limited_future_expression(holds(_, FT), T@=<K, _Vars, T, K) :-
	ground(FT), is_structured_time(FT), !.
limited_future_expression(holds(_, FT), T=<K, _Vars, T, K) :-
	ground(FT), !, expression_to_time(FT, K).
limited_future_expression(happens(_, ET1, _ET2), Expr, _Vars, T, K) :-
	ground(ET1),
	(   is_structured_time(ET1)
	->  Expr = (T @=< ET1)
	;   expression_to_time(ET1, K), Expr = (T =< K)
	).
limited_future_expression(happens(_, _ET1, ET2), Expr, _Vars, T, K) :-
	ground(ET2),
	(   is_structured_time(ET2)
	->  Expr = (T @=< ET2)
	;   expression_to_time(ET2, K), Expr = (T =< K)
	), !.
limited_future_expression(T<K, T<K, Vars, T, K) :- member_equivalent_chk(T, Vars), !.
limited_future_expression(T=<K, T=<K, Vars, T, K) :- member_equivalent_chk(T, Vars), !.
limited_future_expression(T@<K, T@<K, Vars, T, K) :- member_equivalent_chk(T, Vars), !.
limited_future_expression(T@=<K, T@=<K, Vars, T, K) :- member_equivalent_chk(T, Vars), !.
limited_future_expression(K>T, K>T, Vars, T, K) :- member_equivalent_chk(T, Vars), !.
limited_future_expression(K>=T, K>=T, Vars, T, K) :- member_equivalent_chk(T, Vars), !.
limited_future_expression(K@>T, K@>T, Vars, T, K) :- member_equivalent_chk(T, Vars), !.
limited_future_expression(K@>=T, K@>=T, Vars, T, K) :- member_equivalent_chk(T, Vars), !.

		 /*******************************
		 *     dc_resolve_goals/2	*
		 *******************************/

dc_resolve_goals(Goals, NewGoals) :-
	simplify_goal_variants(Goals, Goals_),
	dc_resolve_goals(Goals_, Goals_, NewGoals1),
	check_binders(NewGoals1, NewGoals2),
	(   NewGoals1 \= NewGoals2
	->  collect_waiters(NewGoals2, Waiters, Others),
	    append(Waiters, Others, NewGoals2_),
	    dc_resolve_goals(NewGoals2_, NewGoals2, NewGoals3)
	;   NewGoals2 = NewGoals3
	),
	dc_resolve_goals_handle_failed(NewGoals3, NewGoals).

%	SP11 — the first failed goal decides. If it is non-discardable, or if
%	no other goal shares its last ancestor, we fail, which backtracks into
%	phase 10 and possibly as far as event injection.
dc_resolve_goals_handle_failed(Goals, NewGoals) :-
	select(goal(_ID, Discard, MyFailure, _OurFailures, _SharedVars, EventAncestors, _G),
	       Goals, PrunedGoals),
	MyFailure == failed,
	!,
	(   (   Discard == non_discardable
	    ;	last(EventAncestors, A),
		\+ ( member(goal(_, _, _, _, _, Ancestors, _), PrunedGoals),
		     last(Ancestors, Same), Same == A )
	    )
	->  fail
	;   dc_resolve_goals_handle_failed(PrunedGoals, NewGoals)
	).
dc_resolve_goals_handle_failed(Goals, Goals).

collect_waiters([goal(ID, Discard, MyFailure, OurFailures, Shared, Ancestors, G)|Goals],
		[goal(ID, Discard, MyFailure, OurFailures, Shared, Ancestors, G)|Waiters],
		Others) :-
	once(a_literal(G, W)), W = '$_wait'(_),
	!,
	collect_waiters(Goals, Waiters, Others).
collect_waiters([G|Goals], Waiters, [G|Others]) :- collect_waiters(Goals, Waiters, Others).
collect_waiters([], [], []).

%	SP7 — variant goals are merged, keeping the first. This is what stops
%	duplicate rule instances from multiplying actions.
simplify_goal_variants([goal(ID, Discard, MyFailure, OurFailures, Shared, EventAncestors, G)|Goals],
		       NewGoals) :-
	term_variables(EventAncestors, AncestorVars),
	select(goal(_ID2, Discard2, MyFailure2, OurFailures2, Shared2, EventAncestors2, G2),
	       Goals, Pruned),
	term_variables(EventAncestors2, AncestorVars2),
	( Shared2 == Shared ; ground(Shared2) ),
	variant(Discard+MyFailure+OurFailures+AncestorVars+G,
		Discard2+MyFailure2+OurFailures2+AncestorVars2+G2),
	!,
	simplify_goal_variants([goal(ID, Discard, MyFailure, OurFailures, Shared, EventAncestors, G)|Pruned],
			       NewGoals).
simplify_goal_variants([G|Goals], [G|NewGoals]) :- !, simplify_goal_variants(Goals, NewGoals).
simplify_goal_variants(Goals, Goals).

check_binders(Goals, NewGoals) :-
	member(G, Goals), G \= binder(_, _, _, _), !,
	check_binders(Goals, Goals, NewGoals).
check_binders(_Goals, []).

check_binders([binder(Lambda, Condition, Var, Why)|Goals], All, NewGoals) :- !,
	(   ( var(Var), Lambda = All, call(Condition) )
	->  NewGoals_ = NewGoals
	;   [binder(Lambda, Condition, Var, Why)|NewGoals_] = NewGoals
	),
	check_binders(Goals, All, NewGoals_).
check_binders([X|Goals], All, [X|NewGoals]) :- !, check_binders(Goals, All, NewGoals).
check_binders([], _, []).

dc_resolve_goals([], _, []) :- !.
dc_resolve_goals([binder(Lambda, Condition, Var, Why)|Goals], All,
		 [binder(Lambda, Condition, Var, Why)|NewGoals]) :- !,
	dc_resolve_goals(Goals, All, NewGoals).
dc_resolve_goals([goal(_ID, Discard, _Failed, _, _, _, _)|Goals], All, NewGoals) :-
	Discard == yes, !,
	dc_resolve_goals(Goals, All, NewGoals).
dc_resolve_goals([goal(ID, Discard, MyFailure, OurFailures, SharedVars, EventAncestors, G)|Goals],
		 All, NewGoals_) :-
	var(MyFailure), has_no_future(G, EventAncestors, _Killer),
	!,
	MyFailure = failed,
	NewGoals_ = [goal(ID, Discard, MyFailure, OurFailures, SharedVars, EventAncestors, G)|NewGoals],
	dc_resolve_goals(Goals, All, NewGoals).
dc_resolve_goals([goal(ID, Discard, Failure, Failures, SharedVars, A, G)|Goals], All, NewGoals) :-
	var(Failure),
	resolve_until_action(G, A, Ball, Continuation),
	check_ball3(Ball, Continuation, G),
	(   ( var(Ball) ; Ball == conjunction_prunning )
	->  dc_resolve_goals(Goals, All, NewGoals)
	;   dc_resolve_goals_suspended(G, ID, Discard, Failure, Failures, SharedVars,
				       Goals, Ball, Continuation, All, NewGoals)
	).
dc_resolve_goals([goal(_ID, Discard, failed, OurFailures, _SharedVars, _Ancestors, _G)|Goals],
		 All, NewGoals) :-
	%  resolve_until_action/4 failed. Tolerate it only when this goal is one
	%  of a disjunctive bunch with at least one branch still alive.
	Discard \== non_discardable,
	is_list(OurFailures),
	\+ ground(OurFailures),
	dc_resolve_goals(Goals, All, NewGoals).

check_ball3(Ball, Continuation, G) :-
	(   ( var(Ball), Continuation \== true )
	->  throw(error(lps_inconsistent_ball(G, Ball), _))
	;   true
	).

		 /*******************************
		 *	   suspensions		*
		 *******************************/

dc_resolve_goals_suspended(_TopG, ID, Discard, Failure, Failures, SharedVars, Goals,
			   later(_G, Ancestors), Continuation, AllGoals, NewGoals) :- !,
	%  SP6 — a suspended goal goes to the *back* of the already-resolved
	%  list, with a fresh child ID.
	dc_resolve_goals(Goals, AllGoals, NewGoals_),
	st_goal_id(ChildID), add_goal_child(ID, ChildID),
	append(NewGoals_, [goal(ID, Discard, Failure, Failures, SharedVars, Ancestors, Continuation)],
	       NewGoals).

dc_resolve_goals_suspended(_TopG, ID, Discard, Failure, _Failures, SharedVars, Goals,
			   ite(Ancestors, Cond, Then, Else), Continuation, AllGoals, NewGoals) :- !,
	(   var(Discard) -> RootAncestorDiscard = Discard ; last(Ancestors, RootAncestorDiscard) ),
	st_goal_id(ID1), st_goal_id(ID2),
	add_goal_child(ID, ID1), add_goal_child(ID, ID2),
	simplify_conjunction(Else, Continuation, ElseContinuation),
	simplify_conjunction(Then, Continuation, ThenContinuation),
	append(Goals,
	       [ goal(ID1, RootAncestorDiscard, Cfailed, [Cfailed, Efailed], DiscardE+SharedVars,
		      Ancestors, (Cond, DiscardE = yes, ThenContinuation)),
		 binder(Lambda,
			( no_active_descendents(ID1, Lambda), C_has_failed = yes,
			  discard_all_descendents(ID1, Lambda) ),
			C_has_failed, ite),
		 goal(ID2, DiscardE, Efailed, [Cfailed, Efailed], DiscardE+SharedVars, Ancestors,
		      ('$_wait'(nonvar(C_has_failed)), ElseContinuation)),
		 binder(_, ( Cfailed == failed, Efailed == failed
			   ; Cfailed == failed, nonvar(DiscardE) ), Failure, ite_fail)
	       ], Goals_),
	dc_resolve_goals(Goals_, AllGoals, NewGoals).

dc_resolve_goals_suspended(_G, ID, Discard, _Failure, _Failures, SharedVars, Goals,
			   conjunction(Branches, Gn, Ancestors), Continuation, AllGoals, NewGoals) :- !,
	make_branch_goals(Branches, ID, Discard, Ancestors, (Gn, Continuation), AllS, AllS,
			  SharedVars, ExtraGoals),
	append(ExtraGoals, Goals, Goals_),
	dc_resolve_goals(Goals_, AllGoals, NewGoals).

dc_resolve_goals_suspended(_G, ID, Discard, _OriginalFailed, _Failures, SharedVars, Goals,
			   disjunction(SuspendedG, Answers, Ancestors), Continuation,
			   AllGoals, NewGoals) :- !,
	(   var(Discard) -> RootAncestorDiscard = Discard ; last(Ancestors, RootAncestorDiscard) ),
	(   ( SuspendedG = holds(_F, T), \+ ground(T) )
	->  copy_term(SuspendedG+SharedVars+Ancestors+Continuation, BindingsForFuture)
	;   true
	),
	simplify_conjunction(SuspendedG = Answer, Continuation, SuspCont),
	findall(goal(ChildID, _IgetBoundBelow, __Failed, _OurFailures, SharedVars, Ancestors, SuspCont),
		( member(Answer, Answers), st_goal_id(ChildID), add_goal_child(ID, ChildID) ),
		ExtraGoals),
	bind_discarders_and_shared(ExtraGoals, SharedVars, RootAncestorDiscard),
	length(ExtraGoals, N), length(OurFailures, N),
	(   nonvar(BindingsForFuture)
	->  bind_failure_variables([_FutureGoalBelow|ExtraGoals], [Failed|OurFailures])
	;   bind_failure_variables(ExtraGoals, OurFailures)
	),
	append(ExtraGoals, Goals, Goals_),
	dc_resolve_goals(Goals_, AllGoals, NewGoals_),
	%  A fluent answer set is never final — later actions may change it —
	%  so add one more alternative standing for the unknown future.
	(   nonvar(BindingsForFuture)
	->  BindingsForFuture = SuspendedG_+SharedVars+Ancestors_+Continuation_,
	    st_goal_id(AnotherID), add_goal_child(ID, AnotherID),
	    simplify_conjunction(SuspendedG_, Continuation_, SuspCont_),
	    append(NewGoals_, [goal(AnotherID, RootAncestorDiscard_, Failed, [Failed|OurFailures],
				    SharedVars, Ancestors_, SuspCont_)], NewGoals),
	    last(Ancestors_, RootAncestorDiscard_), RootAncestorDiscard_ = RootAncestorDiscard
	;   NewGoals = NewGoals_
	).

dc_resolve_goals_suspended(_G, ID, Discard, _Failure, _Failures, SharedVars, Goals,
			   l_events_disjunction(l_events(happens(E, T1, T2), _Body), Answers, Ancestors),
			   Continuation, AllGoals, NewGoals) :-
	(   var(Discard) -> RootAncestorDiscard = Discard ; last(Ancestors, RootAncestorDiscard) ),
	findall(goal(ChildID, _IgetBoundBelow, _Failed, _OurFailures, SharedVars,
		     [happens(E, T1, T2)|Ancestors], BodyContinuation),
		( member(l_events(happens(E, T1, T2), Body), Answers),
		  simplify_conjunction(Body, Continuation, BodyContinuation),
		  st_goal_id(ChildID), add_goal_child(ID, ChildID) ),
		ExtraGoals),
	bind_discarders_and_shared(ExtraGoals, SharedVars, RootAncestorDiscard),
	length(ExtraGoals, N), length(OurFailures, N),
	bind_failure_variables(ExtraGoals, OurFailures),
	append(ExtraGoals, Goals, Goals_),
	dc_resolve_goals(Goals_, AllGoals, NewGoals).

dc_resolve_goals_suspended(_G, ID, Discard, _Failure, _Failures, SharedVars, Goals,
			   l_ints_disjunction(l_int(Fluent, _Body), Answers, Ancestors),
			   Continuation, AllGoals, NewGoals) :-
	(   var(Discard) -> RootAncestorDiscard = Discard ; last(Ancestors, RootAncestorDiscard) ),
	findall(goal(ChildID, _IgetBoundBelow, _Failed, _OurFailures, SharedVars, Ancestors,
		     BodyContinuation),
		( member(l_int(Fluent, Body), Answers),
		  simplify_conjunction(Body, Continuation, BodyContinuation),
		  st_goal_id(ChildID), add_goal_child(ID, ChildID) ),
		ExtraGoals),
	bind_discarders_and_shared(ExtraGoals, SharedVars, RootAncestorDiscard),
	length(ExtraGoals, N), length(OurFailures, N),
	bind_failure_variables(ExtraGoals, OurFailures),
	append(ExtraGoals, Goals, Goals_),
	dc_resolve_goals(Goals_, AllGoals, NewGoals).

make_branch_goals([B|Bn], ID, Discard, A, Cont, AllS, [S|Sn], SharedVars,
		  [goal(ChildID, RootAncestorDiscard, _, [], AllS+SharedVars, A,
			(B, S = yes, ControlCont))|Goals]) :- !,
	(   var(Discard) -> RootAncestorDiscard = Discard ; last(A, RootAncestorDiscard) ),
	simplify_conjunction(lps_conjunction_control(AllS), Cont, ControlCont),
	st_goal_id(ChildID), add_goal_child(ID, ChildID),
	make_branch_goals(Bn, ID, Discard, A, Cont, AllS, Sn, SharedVars, Goals).
make_branch_goals([], _, _, _, _, _AllS, [], _, []).

bind_failure_variables(ExtraGoals, OurFailures) :-
	bind_failure_variables(ExtraGoals, OurFailures, OurFailures).

bind_failure_variables([goal(_ID, _, Failed, AllFailures, _, _, _)|Goals], [Failed|Failures],
		       AllFailures) :- !,
	bind_failure_variables(Goals, Failures, AllFailures).
bind_failure_variables([], [], _).

bind_discarders_and_shared([goal(_ID, Discard, _, _, SharedVars, Ancestors, _)|Goals],
			   SharedVars, Discard) :- !,
	last(Ancestors, RootDiscard),
	( var(RootDiscard) -> RootDiscard = Discard ; true ),
	bind_discarders_and_shared(Goals, SharedVars, Discard).
bind_discarders_and_shared([], _SharedVars, _Discard).

		 /*******************************
		 *	    goal children	*
		 *******************************/

/* Only if-then-else consumes the child relation, and it is expensive to
   maintain (non-backtrackable, so it cannot share structure). Programs
   without an if-then-else are observationally identical without it.
*/

add_goal_child(Parent, Child) :-
	(   st_program(P), p_has_ite(P)
	->  st_add_goal_child(Parent, Child)
	;   true
	).

goal_descendent(ID, Descendent) :-
	st_goal_child(ID, Child),
	( Descendent = Child ; goal_descendent(Child, Descendent) ).

no_active_descendents(ID, AllGoals) :-
	member(goal(ID, _, Failed, _, _, _, _), AllGoals), Failed \== failed, !, fail.
no_active_descendents(ID, AllGoals) :-
	member(goal(Descendent, _, Failed, _, _, _, _), AllGoals), Failed \== failed,
	goal_descendent(ID, Descendent), !, fail.
no_active_descendents(_, _).

discard_all_descendents(ID, [goal(_, Discard, _, _, _, _, _)|Goals]) :-
	nonvar(Discard), !,
	discard_all_descendents(ID, Goals).
discard_all_descendents(ID, [goal(ID2, yes, _, _, _, _, _)|Goals]) :-
	( ID = ID2 ; goal_descendent(ID, ID2) ), !,
	discard_all_descendents(ID, Goals).
discard_all_descendents(ID, [_|Goals]) :- discard_all_descendents(ID, Goals).
discard_all_descendents(_, []).

		 /*******************************
		 *	    dc_process/5	*
		 *******************************/

/* Forward reasoning over reactive-rule antecedents.

   SP1 — the accumulator is built with [Rule|Acc], so the surviving rule list
   comes back *reversed* every cycle. That alternation is an accident of
   accumulator-style coding, but it determines the order rules fire in, hence
   goal IDs, hence resolution order, so `legacy_trace` reproduces it.

   SP2 — the leftmost antecedent literal is consumed first, each matching
   body is prepended to what remains, and the resulting rules go in front of
   the rules still to process: depth-first, left to right, source order.

   The accumulator is a ri/2 pair rather than a bare list — see ri_new/2. The
   list in it is exactly the list this predicate used to thread, and NRi is
   still that list, so nothing outside here sees the difference.
*/

dc_process(Rules, Acc0, NRi, AccG, NGi) :-
	ri_new(Acc0, Ri0),
	dc_process_(Rules, Ri0, Ri, AccG, NGi),
	ri_list(Ri, NRi).

dc_process_([], Rs, Rs, NG, NG) :- !.
dc_process_([reactive_rule([], C)|Rs], AccRi, NRi, AccG, NGi) :- !,
	st_goal_id(ID),
	record_rule_fired(ID, C),
	dc_process_(Rs, AccRi, NRi,
		    [goal(ID, non_discardable, _, [], [], [DiscardChildren],
			  (C, DiscardChildren = yes))|AccG],
		    NGi).
dc_process_([composite_event([], happens(CE, Start, End))|Rs], AccRi, NRi, AccG, NGi) :- !,
	st_now(T),
	(   T = End
	->  dc_process_(Rs, AccRi, NRi, [event(happens(CE, Start, End))|AccG], NGi)
	;   ( ground(End), End < T )
	->  dc_process_(Rs, AccRi, NRi, AccG, NGi)
	;   ( ground(End), End > T )
	->  ri_add(composite_event([], happens(CE, Start, End)), AccRi, AccRi1),
	    dc_process_(Rs, AccRi1, NRi, AccG, NGi)
	;   throw(error(lps_inconsistent_ce_time(happens(CE, Start, End), T), _))
	).
dc_process_([Rule|Rs], AccRi, NRi, AccG, NGi) :-
	%  too late to solve, no longer relevant
	Rule =.. [_, A, _],
	st_now(Now), Next is Now + 1,
	member(L, A),
	(   L = holds(_, T_), expression_to_time(T_, T), ground(T), T < Now
	;   L = happens(_, T1_, T2_), expression_to_time(T1_, T1), expression_to_time(T2_, T2),
	    ( ground(T1), T1 < Now - 1 ; ground(T2), T2 < Next - 1 )
	),
	!,
	dc_process_(Rs, AccRi, NRi, AccG, NGi).
dc_process_([Rule|Rs], AccRi, NRi, AccG, NGi) :-
	Rule =.. [F, [E|Ls], C],
	real_time_literal(E, TransformedE),
	!,
	append(TransformedE, Ls, Antecedent),
	NewRule =.. [F, Antecedent, C],
	dc_process_([NewRule|Rs], AccRi, NRi, AccG, NGi).
dc_process_([Rule|Rs], AccRi, NRi, AccG, NGi) :-
	Rule =.. [_, [L|_], _],
	must_be_delayed(L),
	!,
	ri_add(Rule, AccRi, AccRi1),
	dc_process_(Rs, AccRi1, NRi, AccG, NGi).
%	The duplicate check and the expansion that follows it were two clauses;
%	they are one because both need the rule's variant key and computing it
%	twice was a fifth of the run on life.
dc_process_([Rule|Rs], AccRi, NRi, AccG, NGi) :-
	ri_key(Rule, K),
	(   ri_has(Rule, K, AccRi)
	->  dc_process_(Rs, AccRi, NRi, AccG, NGi)
	;   Rule =.. [F, [E|Ls], C],
	    ( must_be_processed_now(E) -> ItMust = true ; ItMust = false ),
	    findall(RR,
		    ( lps_clause(E, Body), append(Body, Ls, Antecedent),
		      RR =.. [F, Antecedent, C] ),
		    NewRules),
	    (	NewRules == []
	    ->	RulesToProcess = Rs
	    ;	append(NewRules, Rs, RulesToProcess)
	    ),
	    (	ItMust == true
	    ->	dc_process_(RulesToProcess, AccRi, NRi, AccG, NGi)
	    ;	ri_add(Rule, K, AccRi, AccRi1),
		dc_process_(RulesToProcess, AccRi1, NRi, AccG, NGi)
	    )
	).

/* The residual-rule accumulator, with a redundant index.

   SP1 keeps this a list in accumulator order, because that order is the order
   the rules fire in next cycle. But the duplicate check in the last clause
   above is a variant test against *everything accumulated so far*, which is
   quadratic in the number of surviving rule instances: on Conway's life it was
   4.7 million =@=/2 calls, 73% of the run.

   So the list is paired with an assoc from a variant-invariant hash to the
   rules carrying it, and the variant test runs over one bucket instead of the
   whole accumulator. The hash is a filter and never an answer: variants always
   hash alike, so a miss is a definite no, and a hit is still confirmed with
   variant/2. The list itself, and therefore the order, is untouched.
*/
ri_new(List, ri(List, Assoc)) :-
	empty_assoc(A0),
	foldl(ri_index, List, A0, Assoc).

ri_list(ri(List, _), List).

ri_index(Rule, A0, A) :- ri_key(Rule, K), ri_index(Rule, K, A0, A).

ri_index(Rule, K, A0, A) :-
	(   get_assoc(K, A0, Bucket)
	->  true
	;   Bucket = []
	),
	put_assoc(K, A0, [Rule|Bucket], A).

ri_add(Rule, AccRi, AccRi1) :- ri_key(Rule, K), ri_add(Rule, K, AccRi, AccRi1).

ri_add(Rule, K, ri(List, A0), ri([Rule|List], A)) :- ri_index(Rule, K, A0, A).

ri_has(Rule, K, ri(_, A)) :-
	get_assoc(K, A, Bucket),
	member_chk_variant(Rule, Bucket).

%	A term carrying attributed variables has no variant hash. Those share one
%	bucket and get the linear scan they had before, which is correct if slow.
ri_key(Rule, K) :- catch(variant_sha1(Rule, K), _, fail), !.
ri_key(_, '$lps_unhashable').

must_be_delayed(holds(_, T_)) :-
	expression_to_time(T_, T), ground(T), st_now(Now), T > Now, !.
must_be_delayed(happens(_, T1_, T2_)) :-
	expression_to_time(T1_, T1), expression_to_time(T2_, T2), st_now(Now),
	( ground(T1), T1 > Now ; ground(T2), T2 > Now + 1 ), !.
must_be_delayed(G) :-
	G =.. [Op, _, _], supported_time_comparison(Op), \+ ground(G), !.

must_be_processed_now(holds(_, T_)) :-
	expression_to_time(T_, T), ground(T), st_now(Now), T =< Now, !.
must_be_processed_now(happens(_, _, T_)) :-
	expression_to_time(T_, T), ground(T), st_now(Now), T =< Now, !.
must_be_processed_now(happens(A, _, _)) :-
	st_program(P), p_macroaction(P, A), \+ p_action(P, A), !.
must_be_processed_now(P) :-
	\+ P = happens(_, _, _), \+ P = holds(_, _).

split_goals_and_events([event(E)|GE], Goals, [E|Events]) :- !,
	split_goals_and_events(GE, Goals, Events).
split_goals_and_events([G|GE], [G|Goals], Events) :- !,
	split_goals_and_events(GE, Goals, Events).
split_goals_and_events([], [], []).
