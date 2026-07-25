/* lps_cli.pl — the command-line surface (§I.8.1).

   A thin layer over the core API. Everything it does is a call to
   lps_session.pl; it owns no engine logic, only argument parsing and
   rendering. That is the point of §I.2's layering — if the CLI needed engine
   knowledge, the core API would be the wrong shape.

     lps run PROGRAM [options]      run to termination
     lps step PROGRAM [options]     run N cycles, print each CycleReport
     lps repl PROGRAM               step, inspect, fork, discard
     lps dump PROGRAM [options]     print the internal form
     lps state PROGRAM              run, then print the final fluents
     lps test [--only S] [...]      the conformance harness
     lps explain PROGRAM --ask Q    the §I.10.5 question forms
     lps timeline PROGRAM           the §I.10.2 lanes and intervals
     lps changes PROGRAM --at N     the §I.10.3 state-change diagram
     lps automaton PROGRAM          the state-transitions diagram (godfa/1)
     lps ide [--port N] [--token T] serve the web IDE (§I.10.1)

   Not implemented, and deliberately reported rather than approximated:
   `dump --syntax legacy` (the internal→surface direction, upstream's
   `dumplps/0`) and `--syntax le`. §I.9.5 makes the round trip a *test*, so a
   half-working reverse translator would be worse than none — it would report
   agreement it had not earned.

   A `.le` program is Logical English: LPS(2) hands it to LE2 (see
   src/edges/lps_le.pl and docs/le_lps_interface.md), which returns internal
   syntax and a provenance list, and refuses with a clear message when LE2 is
   not configured rather than guessing.

   Options
     --syntax legacy|internal|le  default: guessed from the extension
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
:- use_module('../core/lps_explain').
:- use_module('../syntax/lps_internal_syntax').
:- use_module('../syntax/lps_legacy_syntax').
:- use_module(lps_source).
:- use_module(lps_le).

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
	format(user_error, 'usage: lps <run|step|repl|dump|state|test> [PROGRAM] [options]~n', []),
	format(user_error, '  --syntax legacy|internal   --max-time N   --cycles N~n', []),
	format(user_error, '  --trace FILE               --observe "E@T"  --json  --quiet~n', []).

parse_options([], [], []).
parse_options(['--syntax', S|T], F, [syntax(Sy), syntax_out(Sy)|O]) :- !,
	atom_string(Sy, S), parse_options(T, F, O).
parse_options(['--only', S|T], F, [only(S)|O]) :- !, parse_options(T, F, O).
parse_options(['--ask', S|T], F, [ask(S)|O]) :- !, parse_options(T, F, O).
parse_options(['--at', S|T], F, [at(N)|O]) :- !, atom_number(S, N), parse_options(T, F, O).
parse_options(['--port', S|T], F, [port(N)|O]) :- !, atom_number(S, N), parse_options(T, F, O).
parse_options(['--token', S|T], F, [token(S)|O]) :- !, parse_options(T, F, O).
parse_options(['--engine', S|T], F, [engine(S)|O]) :- !, parse_options(T, F, O).
parse_options(['--extended'|T], F, [extended|O]) :- !, parse_options(T, F, O).
parse_options(['--abstract-numbers'|T], F, [abstract_numbers|O]) :- !, parse_options(T, F, O).
parse_options(['--non-reflexive'|T], F, [non_reflexive|O]) :- !, parse_options(T, F, O).
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
	(   option(syntax_out(Out), Options), Out \== internal
	->  format(user_error,
		   'dump --syntax ~w is not implemented: the internal→surface \c
		    direction (upstream dumplps/0) and Logical English are §I.9 work.~n',
		   [Out]),
	    halt(2)
	;   compile_or_die(File, Options, Program),
	    dump_internal(Program, current_output)
	).
run_command(test, Files, Options) :- !,
	harness_args(Files, Options, Args),
	(   current_predicate(runner:main/1)
	->  runner:main(Args)
	;   format(user_error,
		   'the conformance harness is not loaded; run it directly:~n\c
		    ./myswipl.sh -q -g "consult(''conformance/runner.pl'')" \c
		    -g "runner:main([...])" -t halt~n', []),
	    halt(2)
	).
run_command(repl, [File|_], Options) :- !,
	with_session(File, Options, S0),
	format('LPS(2) REPL. `help.` for commands.~n', []),
	repl(S0, []).
run_command(explain, [File|_], Options) :- !,
	run_to_end(File, Options, S),
	(   option(ask(Q), Options)
	->  term_to_atom(Question, Q),
	    lps_session_explain(S, Question, E),
	    explanation_text(E, Lines),
	    forall(member(L, Lines), format('~w~n', [L]))
	;   format(user_error, 'explain needs --ask "why(happened(A), T)"~n', []), halt(2)
	).
run_command(timeline, [File|_], Options) :- !,
	run_to_end(File, Options, S),
	lps_session_timeline(S, timeline(Max, Fluents, lane(_, Ev), lane(_, Cp))),
	format('cycles 0..~w~n', [Max]),
	forall(member(lane(F, Is), Fluents),
	       ( format(atom(A), '~q', [F]), format('  ~w~t~40| ~q~n', [A, Is]) )),
	format('  events~t~40| ~q~n', [Ev]),
	format('  composites~t~40| ~q~n', [Cp]).
run_command(changes, [File|_], Options) :- !,
	run_to_end(File, Options, S),
	( option(at(N), Options) -> true ; N = 1 ),
	lps_session_changes(S, N, changes(_, I, T, U, Persisted)),
	format('cycle ~w~n', [N]),
	forall(member(change(F, A, Src, _), I), format('  + ~q  by ~q  ~w~n', [F, A, Src])),
	forall(member(change(F2, A2, Src2, _), T), format('  - ~q  by ~q  ~w~n', [F2, A2, Src2])),
	forall(member(change(F3, A3, Src3, _), U), format('  ~~ ~q  by ~q  ~w~n', [F3, A3, Src3])),
	format('  = ~q~n', [Persisted]).
%	The run as a finite automaton: every distinct state once, however often
%	it recurs. --abstract-numbers collapses states that differ only in an
%	amount; --non-reflexive drops transitions that change nothing.
run_command(automaton, [File|_], Options) :- !,
	run_to_end(File, Options, S),
	automaton_options(Options, AOpts),
	lps_session_automaton(S, AOpts, automaton(Nodes, Edges)),
	length(Nodes, NN), length(Edges, NE),
	format('~w states, ~w transitions~n', [NN, NE]),
	forall(member(node(Id, Fluents, Cycles, Initial), Nodes),
	       ( ( Initial == true -> Mark = '*' ; Mark = ' ' ),
		 format('~w ~q  cycles ~q~n', [Mark, Id, Cycles]),
		 forall(member(F, Fluents), format('     ~q~n', [F])) )),
	forall(member(edge(From, To, Label, Kind), Edges),
	       format('  ~q -> ~q  ~q  (~w)~n', [From, To, Label, Kind])).
%	`--token T`, or LPS_TOKEN in the environment. A deployment that is
%	reachable from anywhere and has no token is a Prolog interpreter open to
%	the internet, so the server says out loud which of the two it is.
run_command(ide, _, Options) :- !,
	( option(port(Port), Options) -> true ; Port = 3060 ),
	server_token(Options, SOpts),
	(   current_predicate(lps_http:lps_server/2)
	->  lps_http:lps_server(Port, SOpts),
	    ( SOpts == [] -> format('no token: every request is accepted~n', []) ; true ),
	    format('LPS(2) IDE on http://localhost:~w/~n', [Port]),
	    format('press Ctrl-C to stop~n', []),
	    thread_get_message(_)
	;   format(user_error, 'src/edges/lps_http.pl is not loaded~n', []), halt(2)
	).
run_command(C, _, _) :-
	format(user_error, 'unknown command: ~w~n', [C]),
	usage, halt(2).

run_to_end(File, Options, S) :-
	with_session(File, Options, S0),
	lps_session_run(S0, end, S, _).

%	`lps test` is a pass-through to conformance/runner.pl, which is the
%	harness §I.1.1 insists stays independent of both engines — so the CLI
%	translates flags and gets out of the way rather than reimplementing it.
harness_args(_Files, Options, Args) :-
	findall(A, harness_arg(Options, A), Nested),
	append(Nested, Args).

harness_arg(Options, ['--engine', E]) :- option(engine(E), Options).
harness_arg(Options, ['--only', S]) :- option(only(S), Options).
harness_arg(Options, ['--extended']) :- option(extended, Options).
harness_arg(_, ['--variants', none]).

with_session(File, Options, S) :-
	compile_or_die(File, Options, Program),
	lps_session_new(Program, [dc], S0),
	apply_observations(Options, S0, S).

compile_or_die(File, Options, Program) :-
	syntax_of(File, Options, Syntax),
	compile_source(Syntax, File, Program, Diags),
	forall(member(D, Diags),
	       ( format_diag(D, A), format(user_error, '~w~n', [A]) )),
	(   diags_ok(Diags)
	->  true
	;   halt(1)
	).

compile_source(le, File, Program, Diags) :- !,
	lps_le_translate(File, Text, Prov, LeDiags),
	(   diags_ok(LeDiags)
	->  le_terms(Text, Prov, Terms0),
	    companion_terms(File, Extra, ExtraDiags),
	    append(Terms0, Extra, Terms),
	    lps_compile(terms(Terms), internal, [dc], Program, CDiags),
	    append([LeDiags, ExtraDiags, CDiags], Diags)
	;   Program = none, Diags = LeDiags
	).
compile_source(Syntax, File, Program, Diags) :-
	lps_compile(file(File), Syntax, [dc], Program, Diags).

%!	companion_terms(+LEFile, -Terms, -Diags) is det.
%
%	`foo.le` and `foo.lps` compile together, `.le` first. That is the
%	documented escape hatch of docs/le_lps_surface.md §7: `display/2`,
%	Prolog escapes and real-time plumbing are not Logical English and gain
%	nothing from being written as if they were, so they go in a companion
%	file with the right editor mode and the right diagnostics — rather than
%	in an in-band block the LE editor cannot check.
companion_terms(LEFile, Terms, Diags) :-
	(   atom_concat(Base, '.le', LEFile),
	    atom_concat(Base, '.lps', Companion),
	    exists_file(Companion)
	->  legacy_to_internal(file(Companion), [dc], Terms, Diags)
	;   Terms = [], Diags = []
	).

%	Zip the provenance onto the terms read out of LE2's internal text, so
%	every diagnostic downstream reports an `.le` line and column rather
%	than a line of generated Prolog nobody wrote (docs/le_lps_interface.md).
le_terms(Text, Prov, Terms) :-
	setup_call_cleanup(
	    open_string(Text, In),
	    read_le_terms(In, 0, Prov, Terms),
	    close(In)).

read_le_terms(In, N, Prov, Terms) :-
	line_count(In, L0), L is L0 + 1,
	read_term(In, T, [module(lps_cli)]),
	(   T == end_of_file
	->  Terms = []
	;   ( memberchk(prov(N, F, Line, Col, Kind), Prov)
	    -> Loc = src(F, Line, Col, Kind)
	    ;  Loc = L
	    ),
	    N1 is N + 1,
	    Terms = [t(T, Loc)|More],
	    read_le_terms(In, N1, Prov, More)
	).

%	`.pl`, `.lps` are surface syntax; `_.P` and `.lpsw` are the internal
%	form; `.le` is Logical English, which LE2 parses (§I.9). Guessing from
%	the extension is what every caller expects, and --syntax overrides.
syntax_of(_, Options, S) :- option(syntax(S), Options), !.
syntax_of(File, _, internal) :- sub_atom(File, _, _, 0, '_.P'), !.
syntax_of(File, _, internal) :- sub_atom(File, _, _, 0, '.lpsw'), !.
syntax_of(File, _, le) :- sub_atom(File, _, _, 0, '.le'), !.
syntax_of(_, _, legacy).

server_token(Options, [token(T)]) :- option(token(T), Options), T \== '', !.
server_token(_, [token(T)]) :- getenv('LPS_TOKEN', T), T \== '', !.
server_token(_, []).

automaton_options(Options, AOpts) :-
	findall(O, ( member(O, [abstract_numbers, non_reflexive]), memberchk(O, Options) ), AOpts).

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
