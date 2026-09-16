/* rkbook_test.pl — the M19 gate.
 *
 * Every program in examples/collections/kowalski-book/ compiles, runs, and does the thing its
 * header says it does. The second half matters: a book example that runs and
 * produces nothing has not been converted, it has been transcribed.
 *
 *   ./myswipl.sh -q -g "consult('tools/rkbook_test.pl')" -g "rkbook_test:main" -t halt
 */

:- module(rkbook_test, [main/0]).

:- use_module(library(lists)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_diag').

%!	expect(?File, ?Actions) is nondet.
%
%	Actions that must appear somewhere in the trace — the point of the
%	example, in one line.
expect(underground,      [press_alarm, stop_train]).
expect(penalty,          [fine(vandal, 50)]).
expect(fox_crow,         [praise(fox, crow), drop(crow, cheese), pick_up(fox, cheese)]).
expect(louse,            [move_forward, turn_right, stop]).
expect(mars_explorer,    [drive_to(ridge), take_sample(ridge), transmit(ridge)]).
expect(hunger,           [pick_up(me, apple), eat(me, apple)]).
expect(umbrella,         [take(me, umbrella)]).
expect(trolley,          [divert]).
expect(violations,       [issue_fine(visitor, 70), warn(visitor)]).
expect(citizenship_time, [register(pat)]).
expect(event_calculus,   [gives(mary, john, book)]).
expect(plan_generation,  [walk(john, library), give(mary, john, book)]).

main :-
	format('~n=== M19: Kowalski''s book examples in LPS ===~n~n', []),
	findall(R, ( expect(F, As), run_one(F, As, R) ), Rs),
	include(==(ok), Rs, Oks),
	length(Rs, N), length(Oks, NOk),
	format('~n=== ~w/~w programs run and do what they claim ===~n', [NOk, N]),
	( NOk =:= N -> true ; halt(1) ).

run_one(File, Expected, Result) :-
	atomic_list_concat(['examples/collections/kowalski-book/', File, '.lps'], Path),
	(   catch(trace_of(Path, Trace, Status), E, ( Trace = [], Status = E ))
	->  true
	;   Trace = [], Status = failed_to_run
	),
	findall(A, ( member(stage(events, _, Items), Trace), member(A, Items) ), Happened),
	exclude(happened_in(Happened), Expected, Missing),
	(   Missing == []
	->  Result = ok, format('~w~t~24| ~w~n', [File, Status])
	;   Result = failed,
	    format('~w~t~24| ~w — MISSING ~q~n', [File, Status, Missing])
	).

happened_in(Happened, A) :- member(B, Happened), A =@= B, !.
happened_in(Happened, A) :- memberchk(A, Happened).

trace_of(Path, Trace, Status) :-
	lps_compile(file(Path), legacy, [dc], P, Diags),
	( diags_ok(Diags) -> true ; throw(diagnostics(Diags)) ),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, Trace),
	lps_session_status(S, Status).
