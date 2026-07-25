/* lps_time.pl — time, in both of the senses LPS uses it.

   LPS has two clocks. *Cycle time* is an integer that ticks once per cycle;
   it is what `at T` and `from T1 to T2` range over. *Real time* is a
   wall-clock stamp, exposed as the system fluent `real_time/1` and reachable
   from programs as structured dates `Y/M/D`.

   §I.2.3 is the rule that matters here: **time is injected, never read**. The
   old engine calls get_time/1 inside the cycle, which makes its traces
   unreproducible on a different machine — selection_spec SP15, and the reason
   two corpus tests are hostages to machine speed. Here real time is a pure
   function of cycle time:

	real_time(T) = Beginning + T * SecondsPerCycle

   with Beginning taken from `simulatedRealTimeBeginning/1` (parsed once at
   compile time, not at run time) or 0.0, and SecondsPerCycle from
   `simulatedRealTimePerCycle/1` or 1.0. Programs that declared
   `maxRealTime/1` therefore become deterministic, at the cost of their 2021
   goldens — which are regenerated (a decision recorded in
   docs/conformance_report.md).
*/

:- module(lps_time, [
	is_cycle_time/1,
	is_time_expression/1,
	is_structured_time/1,
	is_some_time/1,
	expression_to_time/2,
	misc_to_realtime/2,
	supported_time_comparison/1,
	mixed_time_comparison/2,
	a_real_time_event/2,
	real_time_literal/2,
	clock_of/2,                % +Program, -clock(Beginning, PerCycle)
	real_time_at/3             % +Program, +CycleTime, -RealTimeSeconds
	]).

:- use_module(library(lists)).
:- use_module(lps_program).

is_cycle_time(T) :- nonvar(T), integer(T).

%!	is_time_expression(+T) is semidet.
%
%	No division: `/` is how structured dates are written.
is_time_expression(T) :- nonvar(T), is_time_expression_(T), !.

is_time_expression_(_+_).
is_time_expression_(_-_).
is_time_expression_(_*_).

is_structured_time(T) :- nonvar(T), T = _ / _.

is_some_time(T) :- ( integer(T) ; is_time_expression(T) ; misc_to_realtime(T, _) ), !.

expression_to_time(E, T) :-
	(   ( ground(E), is_time_expression(E) )
	->  T is E
	;   T = E
	).

%!	misc_to_realtime(+ExternalForm, -Seconds) is semidet.
%
%	Fails for cycle time, which is what callers use it to detect.
misc_to_realtime(V, _) :- var(V), !, fail.
misc_to_realtime(A, RT) :- atom(A), !, atom_string(A, S), misc_to_realtime(S, RT).
misc_to_realtime(S, RT) :- string(S), !, parse_time(S, _, RT).
misc_to_realtime(Y/M/D/H/Min/S, RT) :- !, date_time_stamp(date(Y,M,D,H,Min,S,0,-,-), RT).
misc_to_realtime(Y/M/D/H/Min, RT) :- !, date_time_stamp(date(Y,M,D,H,Min,0,0,-,-), RT).
misc_to_realtime(Y/M/D/H, RT) :- !, date_time_stamp(date(Y,M,D,H,0,0,0,-,-), RT).
misc_to_realtime(Y/M/D, RT) :- !, date_time_stamp(date(Y,M,D), RT).
misc_to_realtime(Y/M, RT) :- misc_to_realtime(Y/M/1, RT).

supported_time_comparison(<).
supported_time_comparison(=<).
supported_time_comparison(@<).
supported_time_comparison(@=<).
supported_time_comparison(>).
supported_time_comparison(>=).
supported_time_comparison(@>).
supported_time_comparison(@>=).

%!	mixed_time_comparison(+Goal, -NewGoal) is semidet.
%
%	Rewrite a comparison mixing a structured date with a cycle time so that
%	both sides are dates.
mixed_time_comparison(G, (holds(real_date(RT), T), NewComp)) :-
	ground(G), G =.. [Op, A1, A2], supported_time_comparison(Op),
	(   is_structured_time(A1), integer(A2), T = A2, NewComp =.. [Op, A1, RT]
	;   is_structured_time(A2), integer(A1), T = A1, NewComp =.. [Op, RT, A2]
	),
	!.

a_real_time_event(real_date_begin(RT), RT).
a_real_time_event(real_date_end(RT), RT).
a_real_time_event(end_of_day(RT), RT).

%!	real_time_literal(+Literal, -GoalList) is semidet.
%
%	Rewrite a literal carrying structured dates into a sequence using only
%	cycle time, threading through the `real_date/1` system fluent. Fails
%	when the literal has no real time in it — callers use that as the test.
real_time_literal(holds(_F, T), _) :-
	( var(T) ; is_cycle_time(T) ; is_time_expression(T) ), !, fail.
real_time_literal(holds(F, Y/M/D), [holds(real_date(Y/M/D), T), holds(F, T)]) :- !.
real_time_literal(happens(_E, T1, T2), _) :-
	once(( var(T1) ; is_cycle_time(T1) ; is_time_expression(T1) )),
	( var(T2) ; is_cycle_time(T2) ; is_time_expression(T2) ), !, fail.
real_time_literal(happens(E, RT1, T2),
		  [ happens(real_date_begin(RT1), _, _T1), holds(true, T1), happens(E, T1, T2) ]) :-
	nonvar(RT1), RT1 = _/_/_,
	( var(T2) ; is_cycle_time(T2) ; is_time_expression(T2) ), !.
real_time_literal(happens(E, T1, RT2),
		  [ happens(E, T1, _T2), happens(real_date_end(RT2_), _, _), RT2_ @=< RT2 ]) :-
	nonvar(RT2), RT2 = _/_/_,
	( var(T1) ; is_cycle_time(T1) ; is_time_expression(T1) ), !.
real_time_literal(happens(E, RT1, RT2),
		  [ happens(real_date_begin(RT1), _, _T1), holds(true, T1), happens(E, T1, _T2),
		    happens(real_date_end(RT2_), _, _), RT2_ @=< RT2 ]) :-
	nonvar(RT1), nonvar(RT2), RT1 = _/_/_, RT2 = _/_/_.

		 /*******************************
		 *	  the injected clock	*
		 *******************************/

%!	clock_of(+Program, -Clock) is det.
clock_of(P, clock(Beginning, PerCycle)) :-
	(   prog_setting(P, simulatedRealTimeBeginning, SB),
	    catch(parse_time(SB, B), _, fail)
	->  Beginning = B
	;   prog_setting(P, real_time_beginning, B0)
	->  Beginning = B0
	;   Beginning = 0.0
	),
	(   prog_setting(P, simulatedRealTimePerCycle, S)
	->  PerCycle = S
	;   PerCycle = 1.0
	).

%!	real_time_at(+Program, +CycleTime, -Seconds) is det.
real_time_at(P, T, RT) :-
	clock_of(P, clock(B, S)),
	RT is B + T * S.
