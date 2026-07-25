/* lps_cycle.pl — the LPS cycle (§I.5, §0.3, selection_spec §1).

   One cycle, in the order the engine actually runs it:

     1  termination checks — simulated time up, real time up, lps_terminate
     2  Actions = the events that occurred from T-1 to T
     3  emit the `events` trace record
     4  updateFluents — only under non_prospective; the default (prospective)
	mode advances the state inside phases 7 and 10 instead
     5  dc_process — fire reactive-rule antecedents, producing new goals
     6  split new goals from "interesting" composite events
     7  emit `composites`, advance the state, copy next → current
     8  collect the state fluents
     9  emit the `fluents` trace record
    10  inject observations, resolve goals, re-check preconditions against the
	next state — all inside one conjunction, so a precondition violated at
	the end can backtrack into observation injection at the start (SP11)
    11  recurse

   Phase 4's conditionality is the one place selection_spec corrects §0.3 of
   the plan, and it matters: in prospective mode the state is *never* advanced
   before the rules fire.

   Two deliberate departures from upstream, both required by §I.2.3:

     - No `time_limited/3`. Upstream wraps three phases in a 0.75 s wall-clock
       limit and, on timeout, silently discards that phase's work. That is
       selection_spec SP15, the reason a corpus test can pass one run and fail
       the next. A deterministic engine cannot have it.
     - Real time is computed from cycle time (see lps_time.pl), never read.
*/

:- module(lps_cycle, [
	one_cycle/5,             % +Rules0, +Goals0, -Rules, -Goals, -Status
	initialise_run/3,        % +Program, +Options, -Rules
	interesting_composites/2,
	emit/3,
	update_next_state_fluents/2,
	end_time/2
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(lps_store).
:- use_module(lps_program).
:- use_module(lps_terms).
:- use_module(lps_time).
:- use_module(lps_query).
:- use_module(lps_resolve).

		 /*******************************
		 *	  initialisation	*
		 *******************************/

%!	initialise_run(+Program, +Options, -Rules) is det.
%
%	Everything interpreter:go_/3 does between loading the program and the
%	first cycle: seed the state, emit the cycle-0 `fluents` record, and
%	build the initial rule list.
initialise_run(Program, _Options, Rules) :-
	st_set_now(0),
	initial_state_fluents(Program, Initial),
	st_set_state(Initial),
	p_reactive_rules(Program, R0),
	interesting_composites(Program, Interesting),
	append(R0, Interesting, Rules),
	findall(S, ( st_state(S), \+ system_fluent_template(S) ), IS),
	emit(fluents, 0, IS),
	st_set_now(1),
	add_system_fluents(Program),
	st_set_goal_id(1),
	st_set_goal_children([]).

%	Called, not read out of the captured facts, for the same reason
%	p_observe/3 is: `initial_state/1` may be a rule.
initial_state_fluents(Program, Fluents) :-
	findall(F,
		( p_initial_state(Program, L), member(F, L), \+ system_fluent_template(F) ),
		Fluents).

%	system_fluent/1 — the fluents the engine maintains itself. They live in
%	the state (programs may query real_time/1) but are filtered out of every
%	trace record, exactly as upstream does.
system_fluent_template(real_time(_)).
system_fluent_template(lps_user(_)).
system_fluent_template(lps_user(_, _)).

/* The value of a system fluent is read at the moment of evaluation, from the
   *engine's* clock — st_now/1 — and not from whatever cycle index the caller
   happens to be holding. That distinction is not cosmetic: phase 10 rebuilds
   the next state for cycle T+1 while current_time is still T, so the real_time
   that lands in the next state is T's, not T+1's. Getting it wrong shifts
   every date-driven program by one cycle, which is exactly enough to move
   `end_of_day` events into the wrong cycle.

   The `updating` special case is upstream's: while the state is being advanced
   in the very first cycle, real time has not started moving yet.
*/
system_fluent_value(P, real_time(RT)) :-
	(   prog_setting(P, simulatedRealTimeBeginning, _)
	->  %  A declared simulated beginning *requires* a per-cycle step; without
	    %  one upstream's goal simply fails and the fluent is absent, so the
	    %  same happens here.
	    prog_setting(P, simulatedRealTimePerCycle, SCT),
	    clock_of(P, clock(SB, _)),
	    st_now(This),
	    (   ( st_updating, This == 1 )
	    ->	RT = SB
	    ;	RT is This * SCT + SB
	    )
	;   %  §I.2.3: no wall clock. Real time is a deterministic function of
	    %  cycle time, so maxRealTime programs become reproducible — at the
	    %  cost of their 2021 goldens, which are regenerated.
	    st_now(This),
	    real_time_at(P, This, RT)
	).
system_fluent_value(_, lps_user(unknown_user)).
system_fluent_value(_, lps_user(unknown_user, unknown_email)).

add_system_fluents(Program) :-
	findall(SF, system_fluent_value(Program, SF), SFs),
	st_state_list(L), append(L, SFs, L1), st_set_state(L1).

%!	interesting_composites(+Program, -Rules) is det.
%
%	Composite events worth watching for their own sake: any macro-action
%	that a causal law reacts to, or that has a definition at all. They ride
%	along in the rule list as `composite_event/2` and are what produces the
%	`composites` trace stage.
%
%	The `sort/2` reproduces upstream's setof: it orders by event functor and
%	keeps solutions that differ only in variable identity, which is why a
%	multi-clause macro-action contributes more than one entry. dc_process's
%	variant check collapses them again as they accumulate.
interesting_composites(P, Rules) :-
	findall(composite_event([happens(Template, Start, End)], happens(Template, Start, End)),
		( ( p_terminated(P, CE, _, _)
		  ; p_initiated(P, CE, _, _)
		  ; p_updated(P, CE, _, _, _)
		  ; p_l_events(P, CE, _)
		  ),
		  CE = happens(CE_, _, _),
		  nonvar(CE_),
		  functor(CE_, EF, EN), functor(Template, EF, EN),
		  p_macroaction(P, Template) ),
		L),
	sort(L, Rules).

		 /*******************************
		 *	     the cycle		*
		 *******************************/

%!	one_cycle(+Ri, +Gi, -NRi, -NextGi, -Status) is semidet.
%
%	Exactly one cycle, phases 2..11. Fails if the program fails. Status is
%	`continue` or `stop`.
one_cycle(Ri, Gi, NRi, NextGi, Status) :-
	st_program(P),
	st_now(Time),
	Previous is Time - 1,
	Next is Time + 1,

	% 2, 3 — what occurred, and the record of it
	findall(Action, st_happens(Action, Previous, Time), Actions),
	emit(events, Time, Actions),

	% 4 — destructive state update, non-prospective mode only
	st_enter_step0,
	(   st_option(non_prospective)
	->  update_fluents(Time)
	;   true
	),
	st_leave_step0,

	% 5, 6 — fire antecedents
	dc_process(Ri, [], NRi, [], NewGi_),
	split_goals_and_events(NewGi_, NewGi, CompositeEvents),
	append(Gi, NewGi, NGi),          % SP5 — new goals go at the end

	st_clear_happens,
	add_events(CompositeEvents),

	% 7 — composites, then advance the state on their account
	(   CompositeEvents = [_|_]
	->  emit(composites, Time, CompositeEvents),
	    st_enter_step0,
	    update_next_state_fluents(Previous, false),
	    st_leave_step0,
	    st_copy_next_state
	;   true
	),

	% 8, 9 — the state, and the record of it
	findall(Fluent, ( st_state(Fluent), \+ system_fluent_template(Fluent) ), Fluents_),
	(   st_option(sample(Templates))
	->  findall(Fluent,
		    ( member(Fluent, Templates), dc_query(holds(Fluent, _)) ),
		    IntensionalFluents),
	    append(IntensionalFluents, Fluents_, Fluents)
	;   Fluents = Fluents_
	),
	emit(fluents, Time, Fluents),
	st_clean_state_flag,

	% 10 — one conjunction: injection, resolution, prospective re-check
	(   (   update_events(Time, Next),
		dc_resolve_goals(NGi, GoalTree),
		(   st_option(non_prospective)
		->  true
		;   update_next_state_fluents(Time, true),
		    \+ ( p_d_pre(P, _, Conds), holds_all(Conds, Time, Next) )
		)
	    )
	->  true
	;   fail                          % the program has failed
	),
	(   st_option(non_prospective) -> true ; st_copy_next_state ),

	% 11
	(   GoalTree == end
	->  NextGi = [], Status = stop
	;   NextGi = GoalTree,
	    next_time,
	    Status = continue
	).

next_time :-
	st_now(T), T1 is T + 1, st_set_now(T1).

%	Not forall/2: the event set is a backtrackable global, so a
%	failure-driven loop would undo every addition it just made.
add_events([]).
add_events([E|Es]) :- st_add_happens(E), add_events(Es).

%!	end_time(+Program, -T) is semidet.
end_time(P, T) :- prog_setting(P, maxTime, T), !.
end_time(P, 20) :- \+ prog_setting(P, maxRealTime, _).

		 /*******************************
		 *	   state updates	*
		 *******************************/

%	Destructive update — only reachable under non_prospective.
update_fluents(Time) :-
	st_program(P),
	Previous is Time - 1,
	refresh_system_fluents_in_state(P),
	findall(Fl, ( st_happens(Ev, Previous, Time),
		      p_terminated(P, happens(Ev, Previous, Time), Fl, Cond),
		      holds_all(Cond) ), Terms),
	findall(Fl, ( st_happens(Ev, Previous, Time),
		      p_initiated(P, happens(Ev, Previous, Time), Fl, Cond),
		      holds_all(Cond) ), Inits),
	findall(TFl-IFl, ( st_happens(Ev, Previous, Time),
			   p_updated(P, happens(Ev, Previous, Time), TFl, Old-New, Cond),
			   replace_term(TFl, Old, New, IFl), st_state(TFl),
			   holds_all(Cond) ), Updates),
	forall(( ( member(Fl, Terms) ; member(Fl-_, Updates) ), st_state(Fl) ),
	       del_state(Fl)),
	forall(( ( member(Fl, Inits) ; member(_-Fl, Updates) ), \+ st_state(Fl) ),
	       add_state(Fl)).

add_state(F) :- st_state_list(L), append(L, [F], L1), st_set_state(L1).
del_state(F) :-
	st_state_list(L),
	exclude_unif(F, L, L1),
	st_set_state(L1).

exclude_unif(_, [], []).
exclude_unif(Pat, [X|Xs], Ys) :-
	(   \+ Pat \= X -> Ys = Ys1 ; Ys = [X|Ys1] ),
	exclude_unif(Pat, Xs, Ys1).

refresh_system_fluents_in_state(P) :-
	findall(SF, system_fluent_value(P, SF), SFs),
	refresh_state_(SFs).

refresh_state_([]).
refresh_state_([SF|SFs]) :-
	functor(SF, F, A), functor(Template, F, A),
	del_state(Template), add_state(SF),
	refresh_state_(SFs).

%!	update_next_state_fluents(+Previous, +ExecSystemFluents) is det.
%
%	Build the *next* state from the current one plus the effects of the
%	events ending at Previous+1. Keeping both states available at once is
%	what makes the prospective form of §0.5 — a denial about the state an
%	action would produce — evaluable at all.
%
%	Unserializable actions are applied as a set; everything else is applied
%	one action at a time, so that `updates` effects accumulate over the
%	micro-states while initiates/terminates do not.
update_next_state_fluents(Previous, ExecSystemFluents) :-
	st_program(P),
	Time is Previous + 1,
	st_state_list(State),
	st_set_next_state(State),
	(   ExecSystemFluents == true
	->  findall(SF, system_fluent_value(P, SF), SFs),
	    refresh_next_state_(SFs)
	;   true
	),
	( p_unserializable(P, UActions) -> true ; UActions = [] ),
	findall(happens(Ev, Start, Time),
		( st_happens(Ev, Start, Time), \+ p_editing_action(P, Ev),
		  \+ \+ member(Ev, UActions) ), UAs),
	findall(happens(Ev, Start, Time),
		( st_happens(Ev, Start, Time), \+ member(Ev, UActions) ), SAs),
	findall(Fl, ( member(A, UAs), p_terminated(P, A, Fl, Cond), holds_all(Cond) ), Terms),
	findall(Fl, ( member(A, UAs), p_initiated(P, A, Fl, Cond), holds_all(Cond) ), Inits),
	findall(TFl-IFl,
		( member(A, UAs), p_updated(P, A, TFl, Old-New, Cond),
		  replace_term(TFl, Old, New, IFl), st_next_state(TFl), holds_all(Cond) ),
		Updates),
	forall(( member(Fl, Terms) ; member(Fl-_, Updates) ),
	       ( st_del_next_state(Fl), st_state_changed )),
	forall(( ( member(Fl2, Inits) ; member(_-Fl2, Updates) ), \+ st_next_state(Fl2) ),
	       ( st_add_next_state(Fl2), st_state_changed )),
	forall(member(A2, SAs), apply_serial_action(P, A2)).

refresh_next_state_([]).
refresh_next_state_([SF|SFs]) :-
	functor(SF, F, A), functor(Template, F, A),
	st_del_next_state(Template), st_add_next_state(SF),
	refresh_next_state_(SFs).

apply_serial_action(P, A) :-
	forall(( A = happens(terminate(Fl), _, _)
	       -> true
	       ;  p_terminated(P, A, Fl, Cond), holds_all(Cond) ),
	       ( st_del_next_state(Fl), st_state_changed )),
	forall(( ( A = happens(initiate(Fl2), _, _)
		 -> true
		 ;  p_initiated(P, A, Fl2, Cond2), holds_all(Cond2) ),
		 \+ st_next_state(Fl2) ),
	       ( st_add_next_state(Fl2), st_state_changed )),
	forall(( A = happens(update(Old-New, TFl), _, _)
	       -> replace_term(TFl, Old, New, IFl), st_next_state(TFl)
	       ;  p_updated(P, A, TFl, Old-New, Cond3),
		  replace_term(TFl, Old, New, IFl), st_next_state(TFl), holds_all(Cond3) ),
	       ( st_del_next_state(TFl), st_add_next_state(IFl), st_state_changed )).

		 /*******************************
		 *	 observation injection	*
		 *******************************/

/* SP13. Program-declared observations first, in clause order; then real-time
   observations whose date has arrived; then prolog_events, capped. The
   choicepoint the acceptance test leaves behind is what SP11 backtracks into.
*/

update_events(Time, Next) :-
	st_program(P),
	findall(E, ( p_observe(P, Evs, Next), member(E, Evs) ), Observations),
	(   st_state(real_time(Now))
	->  findall(E,
		    ( catch(p_observe(P, Evs2, RT), _, fail),
		      misc_to_realtime(RT, RTseconds), RTseconds =< Now,
		      \+ ( st_observed_at(RTseconds, T), T \= Time ),
		      st_add_observed_at(RTseconds, Time),
		      member(E, Evs2) ),
		    RTObservations)
	;   RTObservations = []
	),
	append(Observations, RTObservations, AllObservations),
	MaxPrologEvents = 500,
	findnsols(MaxPrologEvents, E,
		  ( prolog_event_template(P, E), p_call(P, E) ),
		  PrologEvents),
	!,
	(   length(PrologEvents, N), N >= MaxPrologEvents
	->  throw(error(lps_too_many_prolog_event_solutions, _))
	;   true
	),
	append(AllObservations, PrologEvents, Events),
	(   Events = [_|_]
	->  inject(P, Events, Time, Next)
	;   true
	).

prolog_event_template(P, E) :-
	p_prolog_events(P, L),
	member(E0, L),
	copy_term(E0, E).

inject(P, Events, Time, Next) :-
	(   p_d_pre(P, both, _)
	->  Prospective = true,
	    ( Time == 0 -> Reject = true ; true )
	;   true
	),
	(   nonvar(Reject)
	->  true
	;   assert_events(Events, Time, Next)
	),
	(   ( p_d_pre(P, current, Conds), holds_all(Conds, Time, Next) )
	->  retract_events(Events, Time, Next)
	;   (   true
	    ;	Prospective == true,
		retract_events(Events, Time, Next)
	    )
	).

assert_events([E|Events], T1, T2) :- !,
	st_add_happens(happens(E, T1, T2)),
	assert_events(Events, T1, T2).
assert_events([], _, _).

retract_events([E|Events], T1, T2) :- !,
	st_del_happens(happens(E, T1, T2)),
	retract_events(Events, T1, T2).
retract_events([], _, _).

		 /*******************************
		 *	  trace emission	*
		 *******************************/

%	§I.5.2 — the engine emits typed trace records; it does not know what a
%	test is. The conformance harness, the timeline view and the explanation
%	forest all read the same records.
%	Items are numbervar'd before being recorded, exactly as
%	interpreter:test/3 does inside its double negation. Without that, a
%	record made now would keep changing as resolution binds the variables
%	it shares — and the `.lpst` contract compares term shape up to variable
%	renaming, so the shape has to be frozen at emission time.
emit(Stage, Cycle, Items) :-
	is_list(Items),
	copy_term(Items, Frozen),
	numbervars(Frozen, 0, _),
	st_trace(stage(Stage, Cycle, Frozen)).
