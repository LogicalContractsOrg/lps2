/* lps_session.pl — the core API (§I.2.2).

   Everything above the core is a caller of these predicates: the CLI, the
   HTTP endpoint, the IDE, the planner, and eventually the agent's control
   loop. There is no other way in.

	lps_compile(+Source, +Syntax, +Options, -Program, -Diagnostics)
	lps_session_new(+Program, +Options, -Session)
	lps_session_observe(+Session0, +Events, -Session)
	lps_session_step(+Session0, -Session, -CycleReport)
	lps_session_run(+Session0, +StopCond, -Session, -Trace)
	lps_session_state(+Session, -Fluents)
	lps_session_fork(+Session, -Session2)

   A *session* is a value: a term holding the current world, the goal queue,
   the surviving rule instances, the cycle number, the event queue and the
   trace. Printing one, diffing two, saving one to a file and forking one are
   therefore all the same operation — you already have the thing.

   Forking (§I.6) falls out of that: `lps_session_fork/2` is a unification.
   Prolog terms are immutable and structure-shared, so the fork costs nothing
   and the two futures cannot interfere. Hypothetical worlds are *closed* —
   only the trunk accepts external observations — and that is enforced here
   rather than left as a convention, because a lookahead that quietly accepted
   exogenous events would be answering a different question from the one the
   caller asked.
*/

:- module(lps_session, [
	lps_compile/5,           % +Source, +Syntax, +Options, -Program, -Diags
	lps_session_new/3,       % +Program, +Options, -Session
	lps_session_observe/3,   % +Session0, +Events, -Session
	lps_session_step/3,      % +Session0, -Session, -CycleReport
	lps_session_run/4,       % +Session0, +StopCond, -Session, -Trace
	lps_session_state/2,     % +Session, -Fluents
	lps_session_fork/2,      % +Session, -Session2
	lps_session_trace/2,     % +Session, -Trace
	lps_session_trim/3,      % +Session0, +KeepCycles, -Session
	lps_session_status/2,    % +Session, -Status
	lps_session_time/2,      % +Session, -Cycle
	lps_session_program/2,   % +Session, -Program
	lps_session_goals/2,     % +Session, -Goals: the outstanding goal queue
	lps_session_outcome/2,   % +Session, -success|failure
	lps_session_kind/2,      % +Session, -trunk|hypothetical
	lps_session_explain/3,   % +Session, +Question, -Explanation
	lps_session_timeline/2,  % +Session, -Timeline
	lps_session_refused/2,   % +Session, -Refused: refused(Cycle, Events, Conditions)
	lps_session_changes/3,   % +Session, +Cycle, -Changes
	lps_session_scene/3,     % +Session, +Cycle, -Scene
	lps_session_scene/4,     % +Session, +Cycle, +Declaration, -Scene
	lps_session_automaton/3, % +Session, +Options, -Automaton
	lps_run/4                % +Source, +Syntax, +Options, -Result
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(lps_diag).
:- use_module(lps_program).
:- use_module(lps_store).
:- use_module(lps_cycle).
:- use_module(lps_time).
:- use_module(lps_explain).
:- use_module(lps_store).

/* session(Id, Program, Options, Rules, Goals, Store, Trace, Status, Kind)
     Trace  : accumulated records, *reversed* (prepending is O(1))
     Status : running | success | failure | terminated(Cause) | stopped
	      | error(E)
     Kind   : trunk | hypothetical
*/

:- dynamic session_counter/1.
session_counter(0).

new_session_id(Id) :-
	retract(session_counter(N)), N1 is N + 1, assertz(session_counter(N1)),
	format(atom(Id), 'lps_session_~w', [N1]).

%!	lps_compile(+Source, +Syntax, +Options, -Program, -Diags) is det.
%
%	Source is file(Path) or terms(List). Syntax is `internal` (the §I.3
%	vocabulary, i.e. a `_.P` file) or `legacy` (surface syntax).
lps_compile(file(Path), internal, Options, Program, Diags) :- !,
	read_source_terms(Path, Terms, ReadDiags),
	(   diags_ok(ReadDiags)
	->  lps_compile_terms(Terms, Options, Program, CompileDiags, Path),
	    append(ReadDiags, CompileDiags, Diags)
	;   Program = none, Diags = ReadDiags
	).
lps_compile(terms(Terms), internal, Options, Program, Diags) :- !,
	lps_compile_terms(Terms, Options, Program, Diags, buffer).
lps_compile(Source, legacy, Options, Program, Diags) :- !,
	legacy_to_internal_terms(Source, Options, Terms, SyntaxDiags),
	%  The origin travels with the terms, so a diagnostic from the *compiler*
	%  still names the surface file the user is editing rather than the
	%  intermediate form they never see.
	( Source = file(Path) -> Origin = Path ; Origin = buffer ),
	(   diags_ok(SyntaxDiags)
	->  lps_compile_terms(Terms, Options, Program, CompileDiags, Origin),
	    append(SyntaxDiags, CompileDiags, Diags)
	;   Diags = SyntaxDiags, Program = none
	).
lps_compile(_, Syntax, _, none, [D]) :-
	format(atom(M), 'unsupported syntax: ~q', [Syntax]),
	diag(error, unsupported_syntax, unknown, M, D).

%	Reading a file is I/O, so it lives at an edge (src/edges/lps_source.pl)
%	and is reached by late binding. The core compiles from *terms*; that is
%	what makes tools/lint_core.pl's assertion about src/core/ true rather
%	than aspirational, and what lets a session be compiled from an editor
%	buffer or an HTTP request body with no file involved.
read_source_terms(Path, Terms, Diags) :-
	(   current_predicate(lps_source:lps_read_terms/3)
	->  lps_source:lps_read_terms(Path, Terms, Diags)
	;   Terms = [],
	    diag(error, no_source_module, unknown,
		 'src/edges/lps_source.pl is not loaded; compile from terms/1 instead', D),
	    Diags = [D]
	).

%	Late binding on the surface-syntax module, so the core does not depend
%	on it and a core-only deployment still links.
legacy_to_internal_terms(Source, Options, Terms, Diags) :-
	(   current_predicate(lps_legacy_syntax:legacy_to_internal/4)
	->  lps_legacy_syntax:legacy_to_internal(Source, Options, Terms, Diags)
	;   Terms = [],
	    diag(error, no_legacy_syntax_module, unknown,
		 'src/syntax/lps_legacy_syntax.pl is not loaded', D),
	    Diags = [D]
	).

%!	lps_session_new(+Program, +Options, -Session) is det.
lps_session_new(Program, Options, Session) :-
	new_session_id(Id),
	install(Program, Options),
	store_fresh,
	st_reset_delta,
	initialise_run(Program, Options, Rules),
	initial_goals(Program, Goals),
	harvest(Store, Delta),
	Session = session(Id, Program, Options, Rules, Goals, Store, Delta, running, trunk).

%	§I.7.5 — under planning mode the planner runs once, up front, and hands
%	the ordinary cycle a list of action sets as goals with pinned times.
%	Nothing downstream knows a planner was involved: preconditions,
%	integrity constraints and the trace all behave exactly as they do for a
%	hand-written program, which is why a planned program's `.lpst` is an
%	ordinary `.lpst`.
initial_goals(Program, Goals) :-
	(   planner_available,
	    lps_planner:planning_mode(Program),
	    lps_planner:plan_goals(Program, Achieve)
	->  engine_options(Program, Opts),
	    st_now(T),
	    (	lps_planner:plan_for(Program, Achieve, Opts, Plan)
	    ->	lps_planner:plan_to_session_goals(Plan, T, Opts, Goals)
	    ;	%  §I.10.5's fourth answerable case for "why did A not happen?":
		%  under planning mode, no plan was found within the horizon.
		%  Recorded rather than inferred, so the explanation can say it
		%  outright instead of falling through to "no goal was created".
		( memberchk(horizon(H), Opts) -> true ; H = default ),
		copy_term(Achieve, Ach), numbervars(Ach, 0, _),
		st_trace(no_plan_found(T, Ach, H)),
		Goals = []
	    )
	;   Goals = []
	).

%	Late binding, so the core links without the planner. Planning is a
%	*mode* (§I.7.2), not a layer everything sits on: a deployment that only
%	ever runs reactive programs should not have to carry a search engine.
planner_available :- current_predicate(lps_planner:plan_for/4).

install(Program, Options) :-
	st_set_program(Program),
	st_set_options(Options).

%	Snapshot the store and hand back this step's trace records, newest
%	first, ready to be prepended to the session's accumulator.
harvest(Store, RevDelta) :-
	st_trace_delta(Stages),
	st_ancestor_delta(Ancestors),
	append(Stages, Ancestors, Delta),
	reverse(Delta, RevDelta),
	store_save(Store).

%!	lps_session_step(+Session0, -Session, -CycleReport) is det.
%
%	Exactly one cycle. No I/O, and fully determined by the session plus
%	whatever was injected with lps_session_observe/3 — which is what makes
%	replay, forking and testing possible at all.
%
%	CycleReport is cycle(Time, Events, Composites, Fluents, Actions): the
%	§I.5.1 by-product that the IDE timeline and the agent's actuator read.
lps_session_step(S0, S, Report) :-
	S0 = session(Id, Program, Options, Ri, Gi, Store0, Trace0, Status0, Kind),
	(   Status0 \== running
	->  S = S0, empty_report(Report)
	;   install(Program, Options),
	    store_load(Store0),
	    st_reset_delta,
	    (	stop_reason(Program, Options, Stop)
	    ->	harvest(Store, Delta),
		append(Delta, Trace0, Trace),
		S = session(Id, Program, Options, Ri, Gi, Store, Trace, Stop, Kind),
		report_of(Delta, Store, Report)
	    ;	run_one(Ri, Gi, Result0),
		replan_if_asked(Program, Ri, Gi, Result0, Result),
		harvest(Store, Delta),
		append(Delta, Trace0, Trace),
		(   Result = ok(NRi, NextGi, CycleStatus)
		->  ( CycleStatus == continue -> St = running ; St = stopped ),
		    S = session(Id, Program, Options, NRi, NextGi, Store, Trace, St, Kind)
		;   Result = error(E)
		->  S = session(Id, Program, Options, Ri, Gi, Store, Trace, error(E), Kind)
		;   S = session(Id, Program, Options, Ri, Gi, Store, Trace, failure, Kind)
		),
		report_of(Delta, Store, Report)
	    )
	).

%	The cut inside run_one/3 is upstream's `!` before recursing: search is
%	breadth-first over the goal list, never across cycles.
run_one(Ri, Gi, Result) :-
	catch(( once(one_cycle(Ri, Gi, NRi, NextGi, CS))
	      ->  Result = ok(NRi, NextGi, CS)
	      ;	  Result = failed
	      ),
	      E,
	      Result = error(E)).

empty_report(cycle(0, [], [], [], [])).

/* §I.7.6 — replanning.

   Under planning mode, a planned action whose precondition no longer holds at
   execution time is not a bug in the plan; it is the world having moved. The
   default is to replan from the current state for the remaining goals, which
   is what makes the mode useful for the agent of Part II, where the world does
   diverge. `on_plan_failure(fail)` keeps the failure, and
   `on_plan_failure(reactive)` drops the plan and lets the ordinary reactive
   rules carry on.

   The replan runs against the state the engine has *now*, not the one the plan
   assumed — that is the whole point — and re-enters through the same door as
   the first plan, as goals with pinned times.
*/
replan_if_asked(Program, Ri, _Gi, failed, Result) :-
	planner_available,
	lps_planner:planning_mode(Program),
	lps_planner:plan_goals(Program, Achieve),
	engine_options(Program, Opts),
	on_plan_failure(Opts, replan),
	!,
	st_now(T),
	(   lps_planner:plan_for(Program, Achieve, Opts, Plan),
	    lps_planner:plan_to_session_goals(Plan, T, Opts, Goals),
	    Goals \== []
	->  run_one(Ri, Goals, Result)
	;   Result = failed
	).
replan_if_asked(Program, Ri, _Gi, failed, Result) :-
	planner_available,
	lps_planner:planning_mode(Program),
	engine_options(Program, Opts),
	on_plan_failure(Opts, reactive),
	!,
	run_one(Ri, [], Result).
replan_if_asked(_, _, _, Result, Result).

/* The program's own `:- lps_engine(planning, [...])` list, with anything the
   caller passed at compile time taking precedence — `./lps run p.lps --search
   bfs` overrides the directive, which is what makes the two searches
   comparable on the same program without editing it.
*/
engine_options(Program, Opts) :-
	(   prog_setting(Program, engine_options, O), is_list(O)
	->  Declared = O
	;   Declared = []
	),
	(   prog_setting(Program, options, CO), is_list(CO)
	->  include(planner_option, CO, Override)
	;   Override = []
	),
	append(Override, Declared, Opts).

planner_option(search(_)).
planner_option(horizon(_)).
planner_option(nodes(_)).
planner_option(max_concurrency(_)).
planner_option(on_plan_failure(_)).

on_plan_failure(Opts, Policy) :-
	(   memberchk(on_plan_failure(P), Opts) -> Policy = P ; Policy = replan ).

/*	The termination clauses of interpreter:cycle/4, lifted out so that a
	stepping caller sees them as a status rather than as a silent stop.

	`unbounded` is the one addition. A program that declares neither
	`maxTime` nor `maxRealTime` stops at LPS1's default of twenty cycles,
	which is right for a batch run and wrong for a *session*: a live
	thermostat with no maxTime is not a program that ends at cycle 20, it is
	a program that ends when you stop it. The caller says which it wants,
	because only the caller knows. */
stop_reason(P, Options, success) :-
	\+ ( memberchk(unbounded, Options), \+ prog_setting(P, maxTime, _) ),
	st_now(Time), end_time(P, M), M < Time, !.
stop_reason(P, _, success) :-
	prog_setting(P, maxRealTime, MaxRT),
	st_now(Time), real_time_at(P, Time, Now), clock_of(P, clock(Begin, _)),
	Duration is Now - Begin, Duration > MaxRT, !.
stop_reason(_, _, terminated(Cause)) :-
	st_now(Time),
	(   st_happens(lps_terminate, _, _), Cause = unknown
	;   st_happens(lps_terminate(Cause), _, _)
	),
	!,
	st_set_terminated(Cause),
	emit(events, Time, [lps_terminate(Cause)]).

report_of(RevDelta, Store, cycle(Time, Events, Composites, Fluents, Actions)) :-
	%  The cycle the records belong to, not the store's clock: by the time a
	%  step returns, next_time/0 has already moved the clock on.
	(   member(stage(_, C, _), RevDelta)
	->  Time = C
	;   arg(1, Store, Time)
	),
	arg(4, Store, Happens),
	reverse(RevDelta, Delta),
	findall(I, ( member(stage(events, _, Is), Delta), member(I, Is) ), Events),
	findall(I, ( member(stage(composites, _, Is), Delta), member(I, Is) ), Composites),
	findall(I, ( member(stage(fluents, _, Is), Delta), member(I, Is) ), Fluents),
	findall(A, member(happens(A, _, _), Happens), Actions).

%!	lps_session_observe(+Session0, +Events, -Session) is det.
%
%	Inject external events, to be seen by the next cycle. §I.6: only the
%	trunk accepts observations; a hypothetical world is closed.
lps_session_observe(S0, Events, S) :-
	S0 = session(Id, Program, Options, Ri, Gi, Store0, Trace, Status, Kind),
	(   Kind == hypothetical
	->  throw(error(lps_hypothetical_world_is_closed(Events), _))
	;   true
	),
	install(Program, Options),
	store_load(Store0),
	st_add_pending(Events),
	store_save(Store),
	S = session(Id, Program, Options, Ri, Gi, Store, Trace, Status, Kind).

%!	lps_session_run(+Session0, +StopCond, -Session, -Trace) is det.
%
%	StopCond is `end`, `cycles(N)` or `until(Goal)` with Goal callable on
%	the session.
lps_session_run(S0, StopCond, S, Trace) :-
	run_until(StopCond, S0, S),
	lps_session_trace(S, Trace).

run_until(end, S0, S) :-
	(   lps_session_status(S0, running)
	->  lps_session_step(S0, S1, _), run_until(end, S1, S)
	;   S = S0
	).
run_until(cycles(N), S0, S) :-
	(   N > 0, lps_session_status(S0, running)
	->  lps_session_step(S0, S1, _), N1 is N - 1, run_until(cycles(N1), S1, S)
	;   S = S0
	).
run_until(until(Goal), S0, S) :-
	(   \+ call(Goal, S0), lps_session_status(S0, running)
	->  lps_session_step(S0, S1, _), run_until(until(Goal), S1, S)
	;   S = S0
	).

lps_session_state(session(_, _, _, _, _, Store, _, _, _), Fluents) :-
	arg(2, Store, State),
	exclude(system_fluent_hidden, State, Fluents).

system_fluent_hidden(real_time(_)).
system_fluent_hidden(lps_user(_)).
system_fluent_hidden(lps_user(_, _)).

%!	lps_session_fork(+Session, -Session2) is det.
%
%	O(1): a session is an immutable term, so the fork shares all of it and
%	the two futures diverge only where they write. This is what §I.7's
%	planner and Part II's consequence-checking are built on.
lps_session_fork(S, S2) :-
	S = session(_, Program, Options, Ri, Gi, Store, Trace, Status, _),
	new_session_id(Id2),
	S2 = session(Id2, Program, Options, Ri, Gi, Store, Trace, Status, hypothetical).

lps_session_trace(session(_, _, _, _, _, _, Rev, _, _), Trace) :- reverse(Rev, Trace).

/* §II.0's bounded trace. A session that runs for a week cannot keep every
   cycle's stage records and derivation forest, so a perpetual driver trims it
   to the last N cycles.

   This is list surgery on an immutable term — no I/O, no clock — so it belongs
   in the core even though only an edge has a reason to call it. What it costs
   is stated rather than hidden: an explanation about a cycle that has been
   trimmed away answers "not recorded", which is the same discipline the
   explanation layer already applies to anything the engine never recorded.
*/
lps_session_trim(S0, Keep, S) :-
	S0 = session(A, B, C, D, E, Store, Rev, G, H),
	arg(1, Store, Now),
	Floor is Now - Keep,
	(   Floor =< 0
	->  S = S0
	;   include(recent_record(Floor), Rev, Rev1),
	    S = session(A, B, C, D, E, Store, Rev1, G, H)
	).

recent_record(Floor, Rec) :-
	(   record_cycle(Rec, C)
	->  C >= Floor
	;   true                      % records with no cycle are kept
	).

record_cycle(stage(_, C, _), C).
record_cycle(action_ancestor(_, C, _), C).
record_cycle(state_change(C, _, _, _, _), C).
record_cycle(plan_step(C, _, _, _), C).
lps_session_status(session(_, _, _, _, _, _, _, Status, _), Status).
lps_session_kind(session(_, _, _, _, _, _, _, _, Kind), Kind).
lps_session_time(session(_, _, _, _, _, Store, _, _, _), Time) :- arg(1, Store, Time).
lps_session_program(session(_, P, _, _, _, _, _, _, _), P).

%!	lps_session_goals(+Session, -Goals) is det.
%
%	The goal queue: what reactive rules have committed this world to and
%	nothing has discharged yet. Read-only, and the one part of the session
%	term an outside caller has a reason to look at — an agent asking what it
%	still owes (src/edges/lps_mcp.pl's `obligations`).
lps_session_goals(session(_, _, _, _, Goals, _, _, _, _), Goals).

lps_session_outcome(S, Outcome) :-
	lps_session_status(S, Status),
	(   Status == failure -> Outcome = failure
	;   Status = error(_) -> Outcome = failure
	;   Outcome = success
	).

		 /*******************************
		 *	   explanations		*
		 *******************************/

/* §I.10.5. The five question forms; `what_if` lives here rather than in
   lps_explain.pl because it is the only one that needs to *run* something, and
   forking is the session's business.
*/
lps_session_explain(S, what_if(Events, T), Explanation) :- !,
	lps_session_program(S, P),
	lps_session_trace(S, Actual),
	what_if(S, Events, T, Hypothetical),
	trace_diff(Hypothetical, Actual, diff(OnlyHypo, OnlyActual)),
	diff_nodes('only in the hypothetical', OnlyHypo, N1),
	diff_nodes('only in what actually happened', OnlyActual, N2),
	append(N1, N2, Kids),
	format(atom(L), 'if ~q had been observed at cycle ~w', [Events, T]),
	(   Kids == []
	->  Verdict = no_difference,
	    Tree = node(L, 'the trace would have been identical', [])
	;   Verdict = differs,
	    Tree = node(L, '', Kids)
	),
	Explanation = explanation(what_if(Events, T), Verdict, Tree),
	P = P.
lps_session_explain(S, Question, Explanation) :-
	lps_session_program(S, P),
	lps_session_trace(S, Trace),
	lps_explain(P, Trace, Question, Explanation).

%	§I.6 in anger: fork the session, inject what the question supposes, run
%	it out, and compare. The branch is closed to anything *else* exogenous,
%	which is what makes the comparison mean what it looks like it means.
what_if(S0, Events, T, Trace) :-
	rewind_to(S0, T, Base),
	lps_session_fork(Base, Fork0),
	Fork0 = session(Id, P, O, Ri, Gi, Store, Tr, St, _),
	Fork = session(Id, P, O, Ri, Gi, Store, Tr, St, trunk),
	inject_and_run(Fork, Events, Trace).

inject_and_run(Fork, Events, Trace) :-
	lps_session_observe(Fork, Events, Injected),
	run_until(end, Injected, Done),
	lps_session_trace(Done, Trace).

%	A session cannot be rewound — it is a value, and the past is a different
%	value. Re-running from the beginning is the honest way to get one, and
%	deterministic replay (§I.2.3) is what makes it give the same past.
rewind_to(S, T, Base) :-
	lps_session_time(S, Now),
	(   Now =< T
	->  Base = S
	;   lps_session_program(S, P), lps_session_options(S, O),
	    lps_session_new(P, O, Fresh),
	    N is T - 1,
	    ( N > 0 -> run_until(cycles(N), Fresh, Base) ; Base = Fresh )
	).

lps_session_options(session(_, _, O, _, _, _, _, _, _), O).

diff_nodes(_, [], []) :- !.
diff_nodes(Label, Diffs, [node(Label, '', Kids)]) :-
	findall(node(L, '', []),
		( member(only(Stage, Cycle, Items), Diffs),
		  format(atom(L), '~w/~w: ~q', [Stage, Cycle, Items]) ),
		Kids).

lps_session_timeline(S, Timeline) :-
	lps_session_program(S, P), lps_session_trace(S, Trace),
	lps_timeline(P, Trace, Timeline).

%	The observed events an integrity constraint refused, each with the cycle
%	it would have happened in (the end of its interval) and the constraint's
%	conditions as they held.
lps_session_refused(S, Refused) :-
	lps_session_trace(S, Trace),
	findall(refused(C, Es, Conds),
		( member(observation_refused(T, Es, Conds), Trace), C is T + 1 ),
		Refused).

lps_session_changes(S, Cycle, Changes) :-
	lps_session_program(S, P), lps_session_trace(S, Trace),
	lps_state_changes(P, Trace, Cycle, Changes).

%	The state-transitions automaton of §I.10.3's second diagram — upstream's
%	godfa/1. Options: abstract_numbers, non_reflexive.
lps_session_automaton(S, Options, Automaton) :-
	lps_session_program(S, P), lps_session_trace(S, Trace),
	lps_automaton(P, Trace, Options, Automaton).

%	The visual mapping evaluates the program's own `display/2` clauses, whose
%	bodies may query the state, so this one needs the store installed — and
%	the store is thread-local, which matters because the HTTP edge answers on
%	a worker thread that has never run a cycle.
lps_session_scene(S, Cycle, Scene) :-
	lps_session_scene(S, Cycle, display, Scene).

%!	lps_session_scene(+Session, +Cycle, +Decl, -Scene) is det.
%
%	Decl is `display` or `display3d` (§I.10.4).
lps_session_scene(S, Cycle, Decl, Scene) :-
	S = session(_, P, Options, _, _, Store, _, _, _),
	install(P, Options),
	store_load(Store),
	lps_session_trace(S, Trace),
	lps_display_scene(P, Trace, Cycle, Decl, Scene).

		 /*******************************
		 *	  whole-program run	*
		 *******************************/

%!	lps_run(+Source, +Syntax, +Options, -Result) is det.
%
%	Compile, make a session, run to termination. Result is
%	run(Outcome, Trace, Diagnostics, Session).
lps_run(Source, Syntax, Options, run(Outcome, Trace, Diags, S)) :-
	lps_compile(Source, Syntax, Options, Program, Diags),
	(   diags_ok(Diags)
	->  lps_session_new(Program, Options, S0),
	    run_until(end, S0, S),
	    lps_session_outcome(S, Outcome),
	    lps_session_trace(S, Trace)
	;   Outcome = failure, Trace = [], S = none
	).
