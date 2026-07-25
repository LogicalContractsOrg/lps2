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
	lps_session_status/2,    % +Session, -Status
	lps_session_time/2,      % +Session, -Cycle
	lps_session_program/2,   % +Session, -Program
	lps_session_outcome/2,   % +Session, -success|failure
	lps_session_kind/2,      % +Session, -trunk|hypothetical
	lps_run/4                % +Source, +Syntax, +Options, -Result
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(lps_diag).
:- use_module(lps_program).
:- use_module(lps_store).
:- use_module(lps_cycle).
:- use_module(lps_time).

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
	(   diags_ok(SyntaxDiags)
	->  lps_compile(terms(Terms), internal, Options, Program, CompileDiags),
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
	    ;	Goals = []
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
	    (	stop_reason(Program, Stop)
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

engine_options(Program, Opts) :-
	(   prog_setting(Program, engine_options, O), is_list(O)
	->  Opts = O
	;   Opts = []
	).

on_plan_failure(Opts, Policy) :-
	(   memberchk(on_plan_failure(P), Opts) -> Policy = P ; Policy = replan ).

%	The termination clauses of interpreter:cycle/4, lifted out so that a
%	stepping caller sees them as a status rather than as a silent stop.
stop_reason(P, success) :-
	st_now(Time), end_time(P, M), M < Time, !.
stop_reason(P, success) :-
	prog_setting(P, maxRealTime, MaxRT),
	st_now(Time), real_time_at(P, Time, Now), clock_of(P, clock(Begin, _)),
	Duration is Now - Begin, Duration > MaxRT, !.
stop_reason(_, terminated(Cause)) :-
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
	st_now(Time), Next is Time + 1,
	inject_all(Events, Time, Next),
	store_save(Store),
	S = session(Id, Program, Options, Ri, Gi, Store, Trace, Status, Kind).

%	Not forall/2: see the note in lps_cycle.pl.
inject_all([], _, _).
inject_all([E|Es], T1, T2) :-
	st_add_happens(happens(E, T1, T2)),
	inject_all(Es, T1, T2).

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
lps_session_status(session(_, _, _, _, _, _, _, Status, _), Status).
lps_session_kind(session(_, _, _, _, _, _, _, _, Kind), Kind).
lps_session_time(session(_, _, _, _, _, Store, _, _, _), Time) :- arg(1, Store, Time).
lps_session_program(session(_, P, _, _, _, _, _, _, _), P).

lps_session_outcome(S, Outcome) :-
	lps_session_status(S, Status),
	(   Status == failure -> Outcome = failure
	;   Status = error(_) -> Outcome = failure
	;   Outcome = success
	).

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
