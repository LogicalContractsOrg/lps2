/* lps_store.pl — the engine's working store.

   §I.2.1 makes a *session* a first-class value: everything mutable lives in a
   term the caller holds, so sessions can be printed, diffed, saved and forked.
   But one cycle of the LPS engine is not a straight-line computation: action
   commitment asserts an event and *undoes it on backtracking* (selection_spec
   SP8), and a precondition violated at the end of phase 10 can backtrack all
   the way into event injection at its start (SP11). A store that only knew how
   to be threaded through a deterministic fold could not express that.

   So the working store is a set of backtrackable global variables, which have
   exactly the semantics the engine needs — an assignment is undone when
   Prolog backtracks past it — and the session term is the store's value at a
   cycle boundary. `lps_session_step/3` loads a session in, runs one cycle,
   reads a session out; nothing outside this module ever sees a global.

   Purity (§I.2.4): b_setval/nb_setval are neither I/O, threads, clock nor
   foreign code. They are process-local and deterministic, so replay, forking
   and multi-session all still hold. The one rule is that they are confined
   *here*: no other core module may touch a global directly.

   Two families, and the difference matters for conformance:

     bset/bget    backtrackable — the event set, the clock, the action-ancestry
		  records. The event set is the important one: SP8 commits an
		  action the moment it is selected and expects it gone if
		  resolution later fails, and SP11 backtracks across whole
		  phases. Ancestry follows the events: an action that was
		  backtracked away did not happen, and neither did its cause.
     nbset/nbget  survives backtracking — the state, the goal-ID counter, the
		  goal-child relation and the real-time observation log, all
		  of which the legacy engine keeps in assert/retract and
		  therefore does *not* undo. Two reasons this is not laziness:
		  goal IDs observably drive if-then-else pruning, so they must
		  keep climbing across a backtrack exactly as upstream's do;
		  and the state is rebuilt by a failure-driven loop whose
		  intermediate results must survive the driving failures.
		  Nothing reads the state expecting a backtrack to restore it
		  — every phase that writes it rebuilds it from scratch.

		  Stage trace records are here too, and for a third reason: a
		  program that *fails* still has a trace for the cycle it failed
		  in, and the `.lpst` contract records that cycle and then
		  `end/-1/failure` (§0.2). Losing it to the failure that ended
		  the run would lose the evidence of what went wrong.

   One corollary bites hard enough to be worth stating: nothing iterating over
   a backtrackable structure may use forall/2. It is `\+ (Cond, \+ Action)`,
   so backtracking into Cond for the next solution undoes what Action just did.
   Use plain recursion.
*/

:- module(lps_store, [
	store_load/1,            % +StoreTerm       — install a session's working data
	store_save/1,            % -StoreTerm
	store_fresh/0,

	st_program/1,            % -Program
	st_set_program/1,        % +Program
	st_options/1,            % -Options
	st_option/1,             % +Option           — semidet
	st_set_options/1,        % +Options

	st_now/1,                % -Time
	st_set_now/1,            % +Time
	st_real_now/1,           % -Time             — now-1 while updating state

	st_state/1,              % ?Fluent           — nondet, insertion order
	st_state_list/1,         % -List
	st_set_state/1,          % +List
	st_next_state/1,         % ?Fluent           — nondet, insertion order
	st_next_state_list/1,    % -List
	st_set_next_state/1,     % +List
	st_add_next_state/1,     % +Fluent           — appends, no duplicates
	st_del_next_state/1,     % +Fluent           — removes all variants-of-instance
	st_copy_next_state/0,

	st_happens/3,            % ?E, ?T1, ?T2      — nondet, insertion order
	st_happens_list/1,       % -List
	st_set_happens/1,        % +List
	st_add_happens/1,        % +happens(E,T1,T2) — appends (backtrackable)
	st_del_happens/1,        % +happens(E,T1,T2) — retractall semantics
	st_clear_happens/0,

	st_pending/1,            % -Events   — injected, awaiting phase 10
	st_set_pending/1,        % +Events
	st_add_pending/1,        % +Events

	st_updating/0,           % semidet
	st_enter_step0/0,
	st_leave_step0/0,

	st_goal_id/1,            % -Id               — increments, survives backtracking
	st_set_goal_id/1,        % +Id
	st_add_goal_child/2,     % +Parent, +Child
	st_goal_child/2,         % ?Parent, ?Child
	st_set_goal_children/1,  % +List
	st_goal_children/1,      % -List

	st_observed_at/2,        % ?RealSeconds, ?Cycle
	st_add_observed_at/2,    % +RealSeconds, +Cycle

	st_state_changed/0,
	st_state_is_clean/0,
	st_clean_state_flag/0,

	st_trace/1,              % +Record   — a stage record (survives failure)
	st_trace_once/1,         % +Record   — …unless this cycle already has it
	st_trace_delta/1,        % -Records  — this cycle's stage records, in order
	st_ancestor/1,           % +Record   — an action-ancestry record
	st_ancestor_delta/1,     % -Records
	st_reset_delta/0,

	st_terminated/1,         % -Cause            — semidet
	st_set_terminated/1      % +Cause
	]).

:- use_module(library(lists)).

/* The store as a term. `store_save/1` and `store_load/1` are each other's
   inverse; a session holds one of these.
*/
store_save(store(Now, State, Next, Happens, Updating, GoalId, Children,
		 Observed, Clean, Trace, Ancestors, Terminated, Pending)) :-
	bget(now, Now),
	nbget(state, State),
	nbget(next_state, Next),
	bget(happens, Happens),
	bget(updating, Updating),
	nbget(goal_id, GoalId),
	nbget(goal_children, Children),
	nbget(observed_at, Observed),
	nbget(clean, Clean),
	nbget(trace, Trace),
	bget(ancestors, Ancestors),
	bget(terminated, Terminated),
	bget(pending, Pending).

store_load(store(Now, State, Next, Happens, Updating, GoalId, Children,
		 Observed, Clean, Trace, Ancestors, Terminated, Pending)) :-
	bset(now, Now),
	nbset(state, State),
	nbset(next_state, Next),
	bset(happens, Happens),
	bset(updating, Updating),
	nbset(goal_id, GoalId),
	nbset(goal_children, Children),
	nbset(observed_at, Observed),
	nbset(clean, Clean),
	nbset(trace, Trace),
	bset(ancestors, Ancestors),
	bset(terminated, Terminated),
	bset(pending, Pending).

store_fresh :-
	store_load(store(0, [], [], [], false, 1, [], [], true, [], [], none, [])).

		 /*******************************
		 *	  raw accessors		*
		 *******************************/

bset(Key, Value) :- global_key(Key, G), b_setval(G, Value).
bget(Key, Value) :- global_key(Key, G), b_getval(G, Value).
nbset(Key, Value) :- global_key(Key, G), nb_setval(G, Value).
nbget(Key, Value) :- global_key(Key, G), nb_getval(G, Value).

/* One fact per key rather than atom_concat/3. The keys are a closed set known
   at compile time, and this is the engine's most-called predicate — a quarter
   of a million atom-table lookups in a ten-cycle program — so the table is
   worth the redundancy. A key not listed here is a typo, and failing loudly
   is better than silently reading a global nobody writes.
*/
global_key(now,            '$lps_now').
global_key(state,          '$lps_state').
global_key(next_state,     '$lps_next_state').
global_key(happens,        '$lps_happens').
global_key(updating,       '$lps_updating').
global_key(goal_id,        '$lps_goal_id').
global_key(goal_children,  '$lps_goal_children').
global_key(observed_at,    '$lps_observed_at').
global_key(clean,          '$lps_clean').
global_key(trace,          '$lps_trace').
global_key(ancestors,      '$lps_ancestors').
global_key(terminated,     '$lps_terminated').
global_key(pending,        '$lps_pending').
global_key(program,        '$lps_program').
global_key(options,        '$lps_options').

		 /*******************************
		 *	 program and options	*
		 *******************************/

st_set_program(P) :- nbset(program, P).
st_program(P) :- nbget(program, P).
st_set_options(O) :- nbset(options, O).
st_options(O) :- nbget(options, O).
st_option(O) :- st_options(Os), memberchk(O, Os).

		 /*******************************
		 *		time		*
		 *******************************/

st_now(T) :- bget(now, T).
st_set_now(T) :- bset(now, T).

%!	st_real_now(-Time) is det.
%
%	interpreter:get_real_now/1. While the state is being advanced the engine
%	pretends the clock has not ticked yet, so fluent queries see the state
%	the events acted on rather than the one they produced.
st_real_now(T) :-
	st_now(Now),
	(   st_updating
	->  T is Now - 1
	;   T = Now
	).

st_updating :- bget(updating, true).
st_enter_step0 :- bset(updating, true).
st_leave_step0 :- bset(updating, false).

		 /*******************************
		 *	      state		*
		 *******************************/

/* The state is an *ordered list*, not a set. Upstream stores it in a dynamic
   predicate, so `state/1` enumerates in assertion order, and copyNextState
   preserves that order while appending newly initiated fluents at the end.
   Solution order feeds first-solution choices downstream (selection_spec
   §2b: `rev_initial` is what separates several bucket-B tests from bucket A),
   so the order is part of the contract, not an implementation detail.
*/

st_state_list(L) :- nbget(state, L).
st_set_state(L) :- nbset(state, L).
st_state(F) :- nbget(state, L), member_i(F, L).

st_next_state_list(L) :- nbget(next_state, L).
st_set_next_state(L) :- nbset(next_state, L).
st_next_state(F) :- nbget(next_state, L), member_i(F, L).

%!	st_add_next_state(+Fluent) is det.
%
%	assertz semantics: append at the end.
st_add_next_state(F) :-
	nbget(next_state, L),
	append(L, [F], L1),
	nbset(next_state, L1).

%!	st_del_next_state(+Fluent) is det.
%
%	retractall semantics: drop every element the (possibly non-ground)
%	pattern unifies with, without binding the pattern.
st_del_next_state(F) :-
	nbget(next_state, L),
	exclude_unifiable(F, L, L1),
	nbset(next_state, L1).

%	Enumeration copies non-ground entries. Upstream stores these in dynamic
%	predicates, so every solution is a fresh instance; sharing them here
%	would let one retrieval bind a term another retrieval still needs.
%
%	It is a linear scan, and upstream's equivalent is a dynamic predicate
%	with first-argument indexing, so the obvious question is whether to keep
%	a redundant index beside the list. Measured before doing it: the largest
%	state in any cycle of any golden trace in the corpus is 21 fluents, the
%	distribution peaks at 7 to 9, and this predicate is 1.6% of Conway's life
%	and 4.0% of prospectiveGoat2 — against an index that would have to be
%	rebuilt every cycle, because st_copy_next_state/0 replaces the state
%	wholesale, and would have to preserve solution order, which is
%	load-bearing (selection_spec §2b). At twenty-one elements that is a loss.
%	The engine's real costs were elsewhere; see the dc_process accumulator in
%	lps_resolve.pl, which was a linear scan over something that does grow.
member_i(X, [Y|_]) :- ( ground(Y) -> X = Y ; copy_term(Y, X) ).
member_i(X, [_|T]) :- member_i(X, T).

exclude_unifiable(_, [], []).
exclude_unifiable(P, [X|Xs], Ys) :-
	(   \+ P \= X
	->  Ys = Ys1
	;   Ys = [X|Ys1]
	),
	exclude_unifiable(P, Xs, Ys1).

st_copy_next_state :-
	nbget(next_state, L),
	nbset(state, L),
	nbset(next_state, []).

		 /*******************************
		 *	      events		*
		 *******************************/

st_happens_list(L) :- bget(happens, L).
st_set_happens(L) :- bset(happens, L).

st_happens(E, T1, T2) :-
	bget(happens, L),
	member_i(happens(E, T1, T2), L).

st_add_happens(H) :-
	bget(happens, L),
	append(L, [H], L1),
	bset(happens, L1).

st_del_happens(H) :-
	bget(happens, L),
	exclude_unifiable(H, L, L1),
	bset(happens, L1).

st_clear_happens :- bset(happens, []).

/* Events injected from outside wait here until phase 10 injects them, rather
   than going straight into the event set. Phase 6 clears the event set — it
   holds *last* cycle's events until then — so anything written directly is
   wiped before it can be seen. Upstream passes external observations into the
   cycle as a parameter for exactly this reason, and they go through the same
   denial checks as program-declared ones once there.

   Backtrackable: SP11 can backtrack into observation injection, and a rejected
   set has to be retried, not lost.
*/
st_pending(L) :- bget(pending, L).
st_set_pending(L) :- bset(pending, L).
st_add_pending(Es) :-
	bget(pending, L), append(L, Es, L1), bset(pending, L1).

		 /*******************************
		 *	    goal identity	*
		 *******************************/

/* Deliberately *not* backtrackable: upstream keeps these in assert/retract,
   so a backtrack leaves the counter where it was. IDs drive if-then-else
   descendant pruning, so the sequence is observable.
*/

st_goal_id(N) :-
	nbget(goal_id, N),
	N1 is N + 1,
	nbset(goal_id, N1).

st_set_goal_id(N) :- nbset(goal_id, N).

st_add_goal_child(P, C) :-
	nbget(goal_children, L),
	nbset(goal_children, [P-C|L]).

st_goal_child(P, C) :-
	nbget(goal_children, L),
	member(P-C, L).

st_set_goal_children(L) :- nbset(goal_children, L).
st_goal_children(L) :- nbget(goal_children, L).

		 /*******************************
		 *	  real-time observations *
		 *******************************/

st_observed_at(RT, T) :- nbget(observed_at, L), member(RT-T, L).
st_add_observed_at(RT, T) :- nbget(observed_at, L), nbset(observed_at, [RT-T|L]).

		 /*******************************
		 *	    state flag		*
		 *******************************/

st_state_changed :- nbset(clean, false).
st_state_is_clean :- nbget(clean, true).
st_clean_state_flag :- nbset(clean, true).

		 /*******************************
		 *	      trace		*
		 *******************************/

/* §I.5.2: the engine emits trace records unconditionally; it has no idea what
   a test is. The conformance harness, the timeline UI and the explanation
   forest are all readers of the same records.

   The store holds only the *current cycle's* records; the session accumulates
   them. Keeping the whole trace here would make every emission copy the whole
   history, which is quadratic over a run of a few thousand cycles — and the
   corpus has one of those.

   Stage records are non-backtrackable and ancestry records are backtrackable,
   and the asymmetry is deliberate. A program that fails still has a trace for
   the cycle it failed in — the `.lpst` contract records that cycle and then
   `end/-1/failure` — so the stage records must survive the failure that ends
   the run. An action that gets backtracked away, on the other hand, did not
   happen, and neither did its ancestry.
*/

st_trace(Record) :-
	nbget(trace, L),
	nbset(trace, [Record|L]).

%!	st_trace_once(+Record) is det.
%
%	Add unless an identical record is already in this cycle's delta.
%	Backtracking makes the engine re-derive the same thing many times over —
%	one ten-cycle corpus program recorded the same prospective violation two
%	thousand times — and an explanation is no better for the repetition. The
%	delta is per-cycle, so the scan is bounded by one cycle's records rather
%	than by the length of the run.
st_trace_once(Record) :-
	nbget(trace, L),
	(   memberchk_eq(Record, L)
	->  true
	;   nbset(trace, [Record|L])
	).

memberchk_eq(X, [Y|_]) :- X == Y, !.
memberchk_eq(X, [_|T]) :- memberchk_eq(X, T).

st_trace_delta(Records) :-
	nbget(trace, L), reverse(L, Records).

st_ancestor(Record) :-
	bget(ancestors, L),
	bset(ancestors, [Record|L]).

st_ancestor_delta(Records) :-
	bget(ancestors, L), reverse(L, Records).

st_reset_delta :-
	nbset(trace, []),
	bset(ancestors, []).

		 /*******************************
		 *	   termination		*
		 *******************************/

st_terminated(Cause) :- bget(terminated, C), C \== none, C = Cause.
st_set_terminated(Cause) :- bset(terminated, Cause).
