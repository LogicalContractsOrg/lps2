/* lps_query.pl — evaluating a literal against the augmented state.

   Two entry points, and the difference between them is easy to lose:

     query/1 (here `dc_query/1`) answers "does this hold *now*", against
	{state, next_state, events, l_int, l_timeless, user Prolog}. It is
	what preconditions, `not`, findall and intensional-fluent bodies use.

     lpsClause/2 answers "what can this literal be reduced to", returning a
	body to keep resolving. It is what the resolver and the reactive-rule
	processor use, and it is the point where clause order becomes
	selection order (selection_spec SP3).

   The two overlap, and upstream says so in a TODO. They are kept apart here
   because they have genuinely different contracts: query/1 must not leave a
   goal half-reduced, lpsClause/2 must.

   Time handling is the subtle part. `check_time_expression/1` pins a literal
   to *now* — where "now" is one cycle back while the state is being advanced
   (`st_real_now/1`). Fluent lookup consults `state` for now and `next_state`
   for now+1, which is what makes prospective constraints (§0.5) — a denial
   about the state an action *would* produce — expressible at all.
*/

:- module(lps_query, [
	dc_query/1,              % +Literal
	evaluate/1,              % +GoalList
	holds_all/1,             % +Conditions
	holds_all/3,             % +Conditions, ?Current, ?Next
	lps_clause/2,            % +Head, -Body           (nondet)
	check_time_expression/1,
	may_bind_time/2,
	st_state_d/1,            % ?Fluent   the state, or a declared default
	st_next_state_d/1,       % ?Fluent
	st_next_state_d/2        % ?Fluent, -Stored
	]).

:- use_module(library(lists)).
:- use_module(lps_store).
:- use_module(lps_program).
:- use_module(lps_terms).
:- use_module(lps_time).

		 /*******************************
		 *	     query		*
		 *******************************/

dc_query(holds(Fl, Now)) :-
	nonvar(Fl), Fl = not(Ps), is_list(Ps), !,
	check_time_expression(Now),
	\+ holds_all(Ps).
dc_query(holds(Fl, Now)) :-
	nonvar(Fl), Fl = not(P), !,
	\+ dc_query(holds(P, Now)).
dc_query(holds(P, T)) :-
	st_real_now(RealNow),
	ground(T), T < RealNow, !,
	throw(error(lps_fluent_out_of_temporal_order(RealNow, holds(P, T)), _)).
dc_query(holds(P, T)) :-
	P \= findall(_, _, _),
	st_program(Prog), p_external(Prog, P), !,
	check_time_expression(T),
	p_call(Prog, P).
dc_query(holds(P, T)) :-
	st_program(Prog),
	\+ ( nonvar(P), p_l_int(Prog, holds(P, _), _) ),
	st_real_now(RealNow), Next is RealNow + 1,
	dc_query_evaluate(P, T, RealNow, Next).
dc_query(holds(P, T)) :- !,
	nonvar(P),                       % otherwise infinite recursion
	st_program(Prog),
	p_l_int(Prog, holds(P, T), B),
	holds_all(B).
dc_query(happens(P, X, Y)) :- !,
	st_happens(P, X, Y).
%	A negated goal is answered the way the goal is: a timeless predicate of
%	the program by its clauses, not by Prolog's not/1 in the module, where
%	the program's timeless predicates do not exist.
dc_query(G) :-
	nonvar(G), ( G = not(N) ; G = (\+ N) ), nonvar(N),
	st_program(Prog), p_timeless(Prog, N), !,
	\+ dc_query(N).
dc_query(P) :-
	st_program(Prog),
	(   \+ p_timeless(Prog, P)
	->  p_call(Prog, P)
	;   p_l_timeless(Prog, P, B), evaluate(B)
	;   p_timeless_fact(Prog, P)
	).

dc_query_evaluate(P, T_, RealNow, Next) :-
	(   ground(T_)
	->  T is T_
	;   T = T_
	),
	dc_query_evaluate_(P, T, RealNow, Next).

dc_query_evaluate_(P, _T, _RealNow, _Next) :-
	nonvar(P), P = findall(X, G, L), !,
	findall(X, evaluate(G), L).
dc_query_evaluate_(P, T, RealNow, Next) :-
	(   st_option(non_prospective)
	->  T = RealNow, st_state_d(P)
	;   T == RealNow
	->  st_state_d(P)                     % leave no choicepoint when we can
	;   ( T = RealNow, st_state_d(P)
	    ; T = Next, st_next_state_d(P)
	    )
	).

/*	Fluent defaults (docs/user/reference/le-for-lps.md §2; `defaults/1`, lps_program).

	A fluent declared with a default is a function of its other arguments,
	total like a Solidity mapping: for a key with no stored entry it holds
	its default. The default is VIRTUAL — never stored, so the state stays as
	small as the program wrote it, and an explanation can say "the default"
	(lps_explain.pl). With the key unbound, only stored entries are
	enumerated: infinitely many keys hold the default, and none is named.
	So `not balance(bob, _)` fails for a defaulted balance: bob has one.
*/
st_state_d(P) :- state_or_default(now, P, _).
st_next_state_d(P) :- state_or_default(next, P, _).

%!	st_next_state_d(?Fluent, -Stored) is nondet.
%
%	As st_next_state_d/1; Stored is false when Fluent holds by default, so
%	an update knows there is no stored fact to replace.
st_next_state_d(P, Stored) :- state_or_default(next, P, Stored).

state_or_default(Which, P, Stored) :-
	(   nonvar(P), st_program(Prog),
	    p_fluent_default(Prog, P, Key, D), key_bound(Key)
	->  (   \+ \+ stored(Which, Key)
	    ->  stored(Which, P), Stored = true
	    ;   functor(P, _, N), arg(N, P, D), Stored = false
	    )
	;   stored(Which, P), Stored = true
	).

stored(now, P) :- st_state(P).
stored(next, P) :- st_next_state(P).

key_bound(Key) :-
	Key =.. [_|As], append(Ks, [_], As), ground(Ks).

%!	holds_all(+Conditions) is nondet.
holds_all(PL) :- evaluate(PL).

%!	holds_all(+Conditions, ?Current, ?Next) is nondet.
%
%	As holds_all/1 but first anchoring the condition's time variables to
%	the current transition. Preconditions come out of the translator with
%	their times already fused into one interval, so binding either the
%	event interval or the first next-state fluent is enough.
holds_all(PL, Current, Next) :-
	(   member(happens(_, Current, Next), PL)
	->  true
	;   once(member(holds(_, Next), PL))
	),
	holds_all(PL).

evaluate([]).
evaluate([P|Rest]) :- !, dc_query(P), evaluate(Rest).
evaluate((P, Rest)) :- dc_query(P), evaluate(Rest).

%!	check_time_expression(?T) is semidet.
check_time_expression(T) :-
	st_real_now(Now),
	(   ground(T)
	->  T =:= Now
	;   T = Now
	).

		 /*******************************
		 *	   clause reduction	*
		 *******************************/

/* NOTE on the missing cuts: clauses 6 and 7 for holds/2 are ordered so that an
   intensional fluent yields its l_int reductions *and then* any extensional
   facts of the same name; the cut sits at the head of clause 7 so nothing
   below it is reachable. That is upstream's behaviour and at least one corpus
   program depends on a predicate being both.
*/

lps_clause(happens(X, Y, Z), Body) :-
	st_program(P),
	p_l_events(P, happens(X, Y, Z), Body).
lps_clause(happens(X, T1_, T2_), Body) :- !,
	expression_to_time(T1_, T1), expression_to_time(T2_, T2),
	Body = [],
	check_time_expression(T2),
	T1 is T2 - 1,
	(   ( nonvar(X), X = not(E) )
	->  \+ st_happens(E, T1, T2)
	;   st_happens(X, T1, T2)
	).
lps_clause(holds(H, T), Body) :-
	nonvar(H), H = not(X), !,
	check_time_expression(T),
	( is_list(X) -> Xs = X ; Xs = [holds(X, T)] ),
	\+ evaluate(Xs),
	Body = [].
lps_clause(holds(H, T), Body) :-
	nonvar(H), H = findall(X, G, L), !,
	check_time_expression(T),
	findall(X, evaluate(G), L),
	Body = [].
lps_clause(holds(P, T), []) :-
	nonvar(P), st_program(Prog), p_external(Prog, P), !,
	check_time_expression(T),
	p_call(Prog, P).
lps_clause(holds(X, T), Body) :-
	nonvar(X),
	st_program(P),
	p_l_int(P, holds(X, T), Body),
	may_bind_time(T, Body).
lps_clause(holds(X, T), Body) :- !,
	check_time_expression(T),
	st_state_d(X),
	Body = [].
lps_clause(tc(P), []) :- !,
	st_program(Prog), p_call(Prog, P).
lps_clause(G, Body) :-
	mixed_time_comparison(G, NewG), !,
	lps_clause(NewG, Body).
%	A negated timeless goal of the program (an LE rule's `it is not the case
%	that …` on a relation with no time): by its clauses, as dc_query/1 does.
lps_clause(G, []) :-
	nonvar(G), ( G = not(N) ; G = (\+ N) ), nonvar(N),
	st_program(Prog), p_timeless(Prog, N), !,
	\+ dc_query(N).
lps_clause(P, []) :-
	st_program(Prog),
	\+ p_timeless(Prog, P), !,
	p_call(Prog, P).
lps_clause(Head, Body) :-
	st_program(Prog),
	p_l_timeless(Prog, Head, Body).
lps_clause(Head, []) :-
	st_program(Prog),
	p_timeless_fact(Prog, Head).

%!	may_bind_time(?T, +Body) is semidet.
%
%	Used when an intensional-fluent clause matches inside an antecedent: if
%	the body mentions no fluent, the head's time must be pinned to the
%	current cycle, or the clause would float.
may_bind_time(_Time, Body) :- a_literal(Body, holds(_, _)), !.
may_bind_time(T_, _) :-
	st_now(T),
	(   ground(T_)
	->  T_ =:= T
	;   T = T_
	).
