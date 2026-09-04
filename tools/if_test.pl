/* if_test.pl — the phase-1 gate of docs/InformPlan.md.
 *
 * Every story in examples/if/ includes the library (world.le), plays its
 * `Test me with` script, and produces the event sequence and the final state
 * that were read by hand from Inform's ideal transcript. The expectations
 * live beside the stories, one Prolog file each in examples/if/expected/,
 * and are regenerated only on purpose:
 *
 *   LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/if_test.pl')" -g "if_test:main" -t halt
 *   LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/if_test.pl')" -g "if_test:record" -t halt
 *
 * The comparison is the conformance contract's (§0.2): per cycle, the event
 * items sorted and compared up to variable renaming, and the same for the
 * fluents of the last cycle. The driver's own events — begin_turn, end_turn,
 * the cmd_* observations — are part of what is compared: they are the script.
 */

:- module(if_test, [main/0, record/0]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_diag').
:- use_module('../src/edges/lps_cli').

story(implicit_connections).
story(nothing_as_term).
story(negated_rp).
story(npc_going).
story(regarding).
story(doors).
story(boston_cream).
story(scene).
story(iqtest).
story(mre).
story(alice).
story(alice_garden).

main :-
	format('~n=== Phase 1: Inform stories on the IF library ===~n~n', []),
	(   getenv('LPS_LE2_LIB', _)
	->  true
	;   format('LPS_LE2_LIB is not set: the stories are Logical English.~n', []),
	    halt(1)
	),
	findall(R, ( story(S), check_one(S, R) ), Rs),
	include(==(ok), Rs, Oks),
	length(Rs, N), length(Oks, NOk),
	format('~n=== ~w/~w stories play as Inform plays them ===~n', [NOk, N]),
	( NOk =:= N -> true ; halt(1) ).

record :-
	forall(story(S),
	       (   observed(S, Events, Fluents, Status),
		   %  A recording of a failed run would be a gate that passes on
		   %  failure; an expectation is only ever a successful play.
		   Status == success
	       ->  expected_path(S, Path),
		   setup_call_cleanup(open(Path, write, Out),
				      ( format(Out, '%  ~w — recorded by tools/if_test.pl; regenerate only on purpose.~n', [S]),
					format(Out, 'status(~q).~n', [Status]),
					forall(member(C-Is, Events), format(Out, 'events(~q, ~q).~n', [C, Is])),
					format(Out, 'fluents(~q).~n', [Fluents]) ),
				      close(Out)),
		   format('recorded ~w (~w)~n', [S, Status])
	       ;   format('NOT recorded: ~w did not run to success~n', [S])
	       )).

check_one(S, Result) :-
	expected_path(S, Path),
	(   \+ exists_file(Path)
	->  Result = failed, format('~w~t~24| no expectation recorded~n', [S])
	;   observed(S, Events, Fluents, Status)
	->  read_expected(Path, ExpStatus, ExpEvents, ExpFluents),
	    (   Status == ExpStatus,
		same_events(Events, ExpEvents),
		same_items(Fluents, ExpFluents)
	    ->  Result = ok, format('~w~t~24| ~w~n', [S, Status])
	    ;   Result = failed,
		first_difference(Events, ExpEvents, Diff),
		format('~w~t~24| ~w — DIFFERS ~q~n', [S, Status, Diff])
	    )
	;   Result = failed, format('~w~t~24| failed to run~n', [S])
	).

expected_path(S, Path) :-
	atomic_list_concat(['examples/if/expected/', S, '.pl'], Path).

read_expected(Path, Status, Events, Fluents) :-
	read_file_to_terms(Path, Terms, []),
	( memberchk(status(Status), Terms) -> true ; Status = unknown ),
	findall(C-Is, member(events(C, Is), Terms), Events),
	( memberchk(fluents(Fluents), Terms) -> true ; Fluents = [] ).

%!	observed(+Story, -Events, -Fluents, -Status) is semidet.
%
%	Events is a list of Cycle-Items for every cycle with at least one event;
%	Fluents the state at the last cycle.
observed(S, Events, Fluents, Status) :-
	atomic_list_concat(['examples/if/', S, '.le'], Path),
	catch(trace_of(Path, Trace, Status0), E, ( Trace = [], Status0 = E )),
	Status = Status0,
	findall(C-Is, ( member(stage(events, C, Is), Trace), Is \== [] ), Events),
	(   aggregate_all(max(C), member(stage(fluents, C, _), Trace), Last),
	    memberchk(stage(fluents, Last, Fluents0), Trace)
	->  Fluents = Fluents0
	;   Fluents = []
	).

%	Through the CLI's own route for a `.le` file: LE2 translates, the
%	companion beside it joins, and the terms compile as internal syntax.
trace_of(Path, Trace, Status) :-
	lps_cli:compile_source(le, Path, [], P, Diags),
	( diags_ok(Diags) -> true ; throw(diagnostics(Diags)) ),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, Trace),
	lps_session_status(S, Status).

same_events(A, B) :-
	length(A, N), length(B, N),
	forall(nth1(I, A, C-Is), ( nth1(I, B, C-Js), same_items(Is, Js) )).

same_items(Is, Js) :-
	length(Is, N), length(Js, N),
	msort(Is, SIs), msort(Js, SJs),
	SIs =@= SJs.

first_difference(A, B, Diff) :-
	(   nth1(I, A, C-Is), ( nth1(I, B, C2-Js) -> true ; C2 = none, Js = [] ),
	    \+ ( C == C2, same_items(Is, Js) )
	->  Diff = cycle(C, got(Is), expected(C2, Js))
	;   length(A, NA), length(B, NB), NA =\= NB
	->  Diff = length(got(NA), expected(NB))
	;   Diff = final_state
	).
