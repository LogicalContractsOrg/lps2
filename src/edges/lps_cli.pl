/* lps_cli.pl — the command-line surface (§I.8.1).

   A thin layer over the core API. Everything it does is a call to
   lps_session.pl; it owns no engine logic, only argument parsing and
   rendering. That is the point of §I.2's layering — if the CLI needed engine
   knowledge, the core API would be the wrong shape.

     lps run PROGRAM [options]      run to termination
     lps step PROGRAM [options]     run N cycles, print each CycleReport
     lps repl PROGRAM               step, inspect, fork, discard, explain
     lps dump PROGRAM [options]     print the internal form
     lps state PROGRAM              run, then print the final fluents

   Options
     --syntax legacy|internal   default: guessed from the extension
     --max-time N               override maxTime/1
     --cycles N                 stop after N cycles
     --trace FILE               write the trace as a .lpst
     --observe "E1,E2@T"        inject events before cycle T
     --json                     machine-readable output
     --quiet
*/

:- module(lps_cli, [ main/0, main/1 ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(option)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../syntax/lps_internal_syntax').
:- use_module(lps_source).

main :-
	current_prolog_flag(argv, Argv),
	main(Argv).

main([]) :- !, usage, halt(2).
main([Command|Rest]) :-
	(   parse_options(Rest, Files, Options)
	->  run_command(Command, Files, Options)
	;   usage, halt(2)
	).

usage :-
	format(user_error, 'usage: lps <run|step|repl|dump|state> PROGRAM [options]~n', []),
	format(user_error, '  --syntax legacy|internal   --max-time N   --cycles N~n', []),
	format(user_error, '  --trace FILE               --observe "E@T"  --json  --quiet~n', []).

parse_options([], [], []).
parse_options(['--syntax', S|T], F, [syntax(Sy)|O]) :- !, atom_string(Sy, S), parse_options(T, F, O).
parse_options(['--max-time', S|T], F, [max_time(N)|O]) :- !, atom_number(S, N), parse_options(T, F, O).
parse_options(['--cycles', S|T], F, [cycles(N)|O]) :- !, atom_number(S, N), parse_options(T, F, O).
parse_options(['--trace', S|T], F, [trace_file(S)|O]) :- !, parse_options(T, F, O).
parse_options(['--observe', S|T], F, [observe(S)|O]) :- !, parse_options(T, F, O).
parse_options(['--json'|T], F, [json|O]) :- !, parse_options(T, F, O).
parse_options(['--quiet'|T], F, [quiet|O]) :- !, parse_options(T, F, O).
parse_options([A|T], [A|F], O) :- \+ sub_atom(A, 0, 2, _, '--'), !, parse_options(T, F, O).
parse_options([A|_], _, _) :-
	format(user_error, 'unknown option: ~w~n', [A]), fail.

		 /*******************************
		 *	    commands		*
		 *******************************/

run_command(run, [File|_], Options) :- !,
	with_session(File, Options, S0),
	stop_condition(Options, Stop),
	lps_session_run(S0, Stop, S, Trace),
	report_run(S, Trace, Options).
run_command(step, [File|_], Options) :- !,
	with_session(File, Options, S0),
	( option(cycles(N), Options) -> true ; N = 1 ),
	step_n(N, S0, S, Options),
	lps_session_trace(S, Trace),
	report_run(S, Trace, Options).
run_command(state, [File|_], Options) :- !,
	with_session(File, Options, S0),
	stop_condition(Options, Stop),
	lps_session_run(S0, Stop, S, _),
	lps_session_state(S, Fluents),
	forall(member(F, Fluents), format('~q~n', [F])).
run_command(dump, [File|_], Options) :- !,
	compile_or_die(File, Options, Program),
	dump_internal(Program, current_output).
run_command(repl, [File|_], Options) :- !,
	with_session(File, Options, S0),
	format('LPS(2) REPL. `help.` for commands.~n', []),
	repl(S0, []).
run_command(C, _, _) :-
	format(user_error, 'unknown command: ~w~n', [C]),
	usage, halt(2).

with_session(File, Options, S) :-
	compile_or_die(File, Options, Program),
	lps_session_new(Program, [dc], S0),
	apply_observations(Options, S0, S).

compile_or_die(File, Options, Program) :-
	syntax_of(File, Options, Syntax),
	lps_compile(file(File), Syntax, [dc], Program, Diags),
	forall(member(D, Diags),
	       ( format_diag(D, A), format(user_error, '~w~n', [A]) )),
	(   diags_ok(Diags)
	->  true
	;   halt(1)
	).

%	`.pl`, `.lps` are surface syntax; `_.P` is the internal form. Guessing
%	from the extension is what every caller expects, and --syntax overrides.
syntax_of(_, Options, S) :- option(syntax(S), Options), !.
syntax_of(File, _, internal) :- sub_atom(File, _, _, 0, '_.P'), !.
syntax_of(File, _, internal) :- sub_atom(File, _, _, 0, '.lpsw'), !.
syntax_of(_, _, legacy).

stop_condition(Options, cycles(N)) :- option(cycles(N), Options), !.
stop_condition(_, end).

step_n(0, S, S, _) :- !.
step_n(N, S0, S, Options) :-
	lps_session_step(S0, S1, Report),
	(   option(quiet, Options) -> true ; print_report(Report) ),
	N1 is N - 1,
	(   lps_session_status(S1, running)
	->  step_n(N1, S1, S, Options)
	;   S = S1
	).

%	--observe "e1,e2@3" — inject events to be seen at cycle 3. The engine
%	never reads a clock, so injecting is the only way anything exogenous
%	gets in (§I.2.3).
apply_observations(Options, S0, S) :-
	findall(Spec, member(observe(Spec), Options), Specs),
	foldl(apply_observation, Specs, S0, S).

apply_observation(Spec, S0, S) :-
	(   split_at_sign(Spec, EventsAtom, TimeAtom),
	    atom_number(TimeAtom, Time)
	->  run_to_cycle(Time, S0, S1),
	    parse_events(EventsAtom, Events),
	    lps_session_observe(S1, Events, S)
	;   parse_events(Spec, Events),
	    lps_session_observe(S0, Events, S)
	).

split_at_sign(Spec, Before, After) :-
	atom_string(A, Spec),
	sub_atom(A, B, _, L, '@'), !,
	sub_atom(A, 0, B, _, Before),
	sub_atom(A, _, L, 0, After).

parse_events(Atom, Events) :-
	term_to_atom(T, Atom),
	( is_list(T) -> Events = T ; comma_list(T, Events) ).

comma_list((A, B), [A|R]) :- !, comma_list(B, R).
comma_list(A, [A]).

run_to_cycle(Time, S0, S) :-
	lps_session_time(S0, Now),
	(   Now >= Time
	->  S = S0
	;   lps_session_status(S0, running)
	->  lps_session_step(S0, S1, _), run_to_cycle(Time, S1, S)
	;   S = S0
	).

		 /*******************************
		 *	    rendering		*
		 *******************************/

report_run(S, Trace, Options) :-
	lps_session_outcome(S, Outcome),
	(   option(trace_file(F), Options)
	->  write_lpst(F, Trace, [dc], Outcome)
	;   true
	),
	(   option(quiet, Options)
	->  true
	;   option(json, Options)
	->  print_json(S, Trace)
	;   print_trace(Trace)
	),
	lps_session_status(S, Status),
	format('~n~w (~w)~n', [Outcome, Status]).

print_trace(Trace) :-
	forall(member(stage(Stage, Cycle, Items), Trace),
	       (   Items == []
	       ->  true
	       ;   format('~w/~w~t~16| ~q~n', [Stage, Cycle, Items])
	       )).

print_report(cycle(Time, Events, Composites, Fluents, _)) :-
	format('cycle ~w~n', [Time]),
	( Events == [] -> true ; format('  events:     ~q~n', [Events]) ),
	( Composites == [] -> true ; format('  composites: ~q~n', [Composites]) ),
	( Fluents == [] -> true ; format('  fluents:    ~q~n', [Fluents]) ).

%	Deliberately hand-rolled rather than pulled from library(http/json):
%	the CLI is an edge, but a JSON dependency here would be the first step
%	towards one in the core.
print_json(S, Trace) :-
	lps_session_outcome(S, Outcome),
	lps_session_time(S, Time),
	format('{"outcome":"~w","cycles":~w,"trace":[', [Outcome, Time]),
	forall_with_commas(stage(St, C, I), member(stage(St, C, I), Trace),
			   format('{"stage":"~w","cycle":~w,"items":~q}', [St, C, I])),
	format(']}~n', []).

forall_with_commas(Template, Goal, Action) :-
	findall(Template, Goal, L),
	forall_commas_(L, Template, Action).

forall_commas_([], _, _).
forall_commas_([X|Xs], Template, Action) :-
	\+ \+ ( Template = X, call(Action) ),
	( Xs == [] -> true ; write(',') ),
	forall_commas_(Xs, Template, Action).

		 /*******************************
		 *	      REPL		*
		 *******************************/

/* Where §I.6 pays off interactively: fork, explore, discard, return to the
   trunk. Sessions are values, so the stack of forks is just a list.
*/
repl(S, Stack) :-
	lps_session_time(S, T),
	lps_session_kind(S, Kind),
	(   Kind == hypothetical
	->  format('lps[~w, hypothetical]> ', [T])
	;   format('lps[~w]> ', [T])
	),
	flush_output,
	read_term(user_input, Cmd, []),
	(   Cmd == end_of_file -> nl
	;   repl_command(Cmd, S, Stack)
	).

repl_command(quit, _, _) :- !.
repl_command(help, S, Stack) :- !,
	format('  step.  run.  state.  trace.  fork.  discard.  quit.~n', []),
	repl(S, Stack).
repl_command(step, S0, Stack) :- !,
	lps_session_step(S0, S, Report), print_report(Report), repl(S, Stack).
repl_command(run, S0, Stack) :- !,
	lps_session_run(S0, end, S, _), repl(S, Stack).
repl_command(state, S, Stack) :- !,
	lps_session_state(S, F), forall(member(X, F), format('  ~q~n', [X])), repl(S, Stack).
repl_command(trace, S, Stack) :- !,
	lps_session_trace(S, T), print_trace(T), repl(S, Stack).
repl_command(fork, S, Stack) :- !,
	lps_session_fork(S, S2),
	format('forked; `discard.` returns to the trunk~n', []),
	repl(S2, [S|Stack]).
repl_command(discard, _, [S|Stack]) :- !,
	format('back to the trunk~n', []),
	repl(S, Stack).
repl_command(discard, S, []) :- !,
	format('nothing to discard: this is the trunk~n', []),
	repl(S, []).
repl_command(C, S, Stack) :-
	format('? ~q~n', [C]), repl(S, Stack).
