/* lps_cli.pl — the command-line surface (§I.8.1).

   A thin layer over the core API. Everything it does is a call to
   lps_session.pl; it owns no engine logic, only argument parsing and
   rendering. That is the point of §I.2's layering — if the CLI needed engine
   knowledge, the core API would be the wrong shape.

     lps run PROGRAM [options]      run to termination
     lps step PROGRAM [options]     run N cycles, print each CycleReport
     lps repl PROGRAM               step, inspect, fork, discard
     lps dump PROGRAM [options]     print the internal form
     lps solidity PROGRAM           the program as a Solidity contract, or why not
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

   A `.le` program is Logical English: LPS2 hands it to LE2 (see
   src/edges/lps_le.pl and docs/dev/le-lps-interface.md), which returns internal
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
:- use_module('../syntax/lps_surface_write').
:- use_module(lps_sandbox).
:- use_module('../syntax/lps_legacy_syntax').
:- use_module('../syntax/lps_pddl').
:- use_module('../syntax/lps_drools').
:- use_module(lps_source).
:- use_module(lps_le).
:- use_module(lps_live).
:- use_module(lps_play).
:- use_module('../syntax/lps_inform').
:- use_module('../syntax/lps_solidity').

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
	format(user_error, 'usage: lps <command> [PROGRAM] [options]~n', []),
	format(user_error, '  run step repl state dump test live play pddl drools inform solidity~n', []),
	format(user_error, '  explain timeline changes automaton ide~n', []),
	format(user_error, '  --syntax legacy|internal|le   --max-time N   --cycles N~n', []),
	format(user_error, '  --sandbox                     refuse Prolog that reaches the machine~n', []),
	format(user_error, '  --trace FILE   --observe "E@T"   --json   --quiet~n', []),
	format(user_error, '  --ask QUESTION   --at N   --port N   --engine E   --only S~n', []),
	format(user_error, '  planning: --search bfs|greedy|auto   --horizon N   --nodes N~n', []).

parse_options([], [], []).
parse_options(['--syntax', S|T], F, [syntax(Sy), syntax_out(Sy)|O]) :- !,
	atom_string(Sy, S), parse_options(T, F, O).
parse_options(['--only', S|T], F, [only(S)|O]) :- !, parse_options(T, F, O).
parse_options(['--ask', S|T], F, [ask(S)|O]) :- !, parse_options(T, F, O).
parse_options(['--at', S|T], F, [at(N)|O]) :- !, atom_number(S, N), parse_options(T, F, O).
parse_options(['--port', S|T], F, [port(N)|O]) :- !, atom_number(S, N), parse_options(T, F, O).
parse_options(['--token', S|T], F, [token(S)|O]) :- !, parse_options(T, F, O).
parse_options(['--engine', S|T], F, [engine(S)|O]) :- !, parse_options(T, F, O).
%	The sandbox is the server's default and not the CLI's — your own file on
%	your own machine — so here it is a flag.
parse_options(['--sandbox'|T], F, [sandbox(true)|O]) :- !, parse_options(T, F, O).
parse_options(['--search', S|T], F, [search(Sy)|O]) :- !, atom_string(Sy, S), parse_options(T, F, O).
parse_options(['--horizon', S|T], F, [horizon(N)|O]) :- !, atom_number(S, N), parse_options(T, F, O).
parse_options(['--nodes', S|T], F, [nodes(N)|O]) :- !, atom_number(S, N), parse_options(T, F, O).
parse_options(['--cycle-ms', S|T], F, [cycle_ms(N)|O]) :- !, atom_number(S, N), parse_options(T, F, O).
parse_options(['--facts', S|T], F, [facts(S)|O]) :- !, parse_options(T, F, O).
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
	(   option(syntax_out(legacy), Options)
	->  /*  upstream's `dumplps/0`. The writer checks itself — it re-reads what
	        it wrote and compares term by term — and says so on stderr if the
	        round trip failed, rather than handing over a program that no
	        longer means what it meant. */
	    /*  `--syntax` sets both ends, and for `dump` it means the *output*:
	        the input is still whatever the file is. Without this,
	        `--syntax legacy` on a `.le` told the reader to parse Logical
	        English as LPS surface syntax. */
	    exclude(input_syntax_option, Options, ReadOptions),
	    compile_or_die(File, ReadOptions, Program),
	    with_output_to(string(Internal), dump_internal(Program, current_output)),
	    internal_terms_of(Internal, Terms),
	    internal_to_surface(Terms, Text, Diags),
	    write(Text),
	    forall(member(diag(_, _, _, M, _), Diags),
		   format(user_error, 'warning: ~w~n', [M]))
	;   option(syntax_out(Out), Options), Out \== internal
	->  format(user_error,
		   'dump --syntax ~w is not implemented: Logical English is §I.9 \c
		    work — the internal\u2192LE direction lives in LE2 \c
		    (le_lps_write.pl).~n',
		   [Out]),
	    halt(2)
	;   compile_or_die(File, Options, Program),
	    dump_internal(Program, current_output)
	).

%	Misc ▸ Deploy as Solidity, from the shell: the contract on stdout, or
%	what forbids a straight translation on stderr (exit 1). `--json` prints
%	the sandbox address as well.
run_command(solidity, [File|_], Options) :- !,
	compile_or_die(File, Options, Program),
	read_file_to_string(File, Text, []),
	(   sub_atom(File, _, _, 0, '.le')
	->  catch(lps_le_templates(Text, File, Ts), _, Ts = [])
	;   Ts = []
	),
	lps_to_solidity(Program, [templates(Ts), source(Text), origin(File)], R),
	(   R = solidity(Sol, _, Notes)
	->  write(Sol),
	    forall(member(D, Notes), ( format_diag(D, A), format(user_error, '~w~n', [A]) )),
	    (   option(json, Options)
	    ->  solidity_sandbox_url(Sol, URL), format(user_error, 'sandbox: ~w~n', [URL])
	    ;   true
	    )
	;   R = refused(Ds),
	    format(user_error, 'not translatable to Solidity:~n', []),
	    forall(member(D, Ds), ( format_diag(D, A), format(user_error, '  ~w~n', [A]) )),
	    halt(1)
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
	format('LPS2 REPL. `help.` for commands.~n', []),
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
/* `lps live PROGRAM` — a perpetual session on the terminal (§II.0). Type an
   event term to inject it; `pause`, `resume`, `stop` do what they say. The
   same driver the IDE's live panel uses, with stdin as the mailbox. */
/* `lps pddl DOMAIN PROBLEM` — plan a PDDL problem with the LPS planner
   (M12a). The translation is a front end like LE2's: internal syntax plus
   provenance, and everything downstream is unchanged. */
run_command(pddl, [Domain, Problem|_], Options) :- !,
	lps_pddl:pddl_to_internal(Domain, Problem, Terms0, Diags),
	forall(member(D, Diags), ( format_diag(D, A), format(user_error, '~w~n', [A]) )),
	( option(horizon(H), Options) -> true ; H = 20 ),
	( option(search(Se), Options) -> true ; Se = auto ),
	( option(max_time(MT), Options) -> true ; MT is H + 4 ),
	append(Terms0,
	       [t((:- lps_engine(planning, [search(Se), horizon(H), max_concurrency(1)])), src(Domain, 1, 0, pddl)),
		t(maxTime(MT), src(Domain, 1, 0, pddl))],
	       Terms),
	lps_compile(terms(Terms), internal, [dc], Program, CDiags),
	(   diags_ok(CDiags)
	->  lps_session_new(Program, [dc], S0),
	    lps_session_run(S0, end, S, Trace),
	    pddl_report(Domain, Problem, S, Trace, Options)
	;   forall(member(D2, CDiags), ( format_diag(D2, A2), format(user_error, '~w~n', [A2]) )),
	    halt(1)
	).
/* `lps drools FILE.drl [--facts "f(a), g(b)"]` — run a DRL rule base through
   LPS (M12d). The procedural leaves are reported, not transpiled (§IV.1). */
run_command(drools, [File|_], Options) :- !,
	lps_drools:drl_to_internal(File, Terms0, Diags),
	forall(member(D, Diags), ( format_diag(D, A), format(user_error, '~w~n', [A]) )),
	( option(facts(FS), Options) -> parse_fact_list(FS, Facts) ; Facts = [] ),
	( option(max_time(MT), Options) -> true ; MT = 8 ),
	Src = src(File, 1, 0, drl),
	append(Terms0, [t(initial_state(Facts), Src), t(maxTime(MT), Src)], Terms),
	lps_compile(terms(Terms), internal, [dc], Program, CDiags),
	(   diags_ok(CDiags)
	->  lps_session_new(Program, [dc], S0),
	    lps_session_run(S0, end, S, Trace),
	    report_run(S, Trace, Options)
	;   forall(member(D2, CDiags), ( format_diag(D2, A2), format(user_error, '~w~n', [A2]) )),
	    halt(1)
	).
run_command(live, [File|_], Options) :- !,
	compile_or_die(File, Options, Program),
	( option(cycle_ms(Ms), Options) -> LOpts = [cycle_ms(Ms)] ; LOpts = [] ),
	lps_live:live_start(Program, LOpts, Id),
	format('live session ~w — type an event term, or pause/resume/stop.~n', [Id]),
	live_repl(Id).
/* `lps play STORY.le` — an interactive-fiction story on the terminal
   (docs/project/plans/InformPlan.md phase 2). Type what a player types; `commands` (or
   `help`) lists what would work from here; `why` explains the
   last turn, `!term` injects a raw event on the player's channel, `fork`
   starts a second game from here (`switch ID`, `games`, and `diff` against the
   game it was forked from), `quit` leaves. Logical English only, so
   LPS_LE2_LIB must be set. */
/* `lps inform STORY.ni [--out DIR]` — Inform 7 assertions as a Logical English
   story on examples/if/world.le. Printed, or written as DIR/NAME.le and
   DIR/NAME.lps beside a copy of the library, so `lps run` and `lps play` take
   them. `lps run STORY.ni` and `lps play STORY.ni` convert on the way in. */
run_command(inform, [File|_], Options) :- !,
	lps_inform:inform_to_le(File, LE, Companion, Diags),
	forall(member(D, Diags), ( format_diag(D, A), format(user_error, '~w~n', [A]) )),
	(   option(out(Dir0), Options)
	->  atom_string(Dir, Dir0), make_directory_path(Dir),
	    file_base_name(File, Base), file_name_extension(Stem, _, Base),
	    lps_inform:story_name(Stem, Name),
	    atomic_list_concat([Dir, '/', Name, '.le'], LEFile),
	    atomic_list_concat([Dir, '/', Name, '.lps'], CFile),
	    atomic_list_concat([Dir, '/world.le'], WFile),
	    write_text(LEFile, LE), write_text(CFile, Companion),
	    (   exists_file(WFile) -> true
	    ;   lps_le:lps2_root(Root), atomic_list_concat([Root, '/examples/if/world.le'], W),
		read_file_to_string(W, WT, [encoding(utf8)]), write_text(WFile, WT)
	    ),
	    format('~w~n~w~n', [LEFile, CFile])
	;   format('~w~n% ---- companion ----~n~w', [LE, Companion])
	).
run_command(play, [File|_], Options) :- !,
	( option(model(M0), Options) -> atom_string(M, M0) ; M = null ),
	catch(lps_play:play_start(file(File), [model(M)], Id), play_failed(Ds),
	      ( forall(member(D, Ds), ( lps_diag:diag_text(D, T), format(user_error, '~w~n', [T]) )),
		halt(1) )),
	lps_play:play_status(Id, St),
	St.transcript = [Opening|_],
	forall(member(L, Opening.lines), format('~w~n', [L])),
	format('~n(type a command; `commands` lists what would work from here, `why` explains the last turn, `quit` leaves)~n', []),
	play_repl(Id).
run_command(ide, _, Options) :- !,
	( option(port(Port), Options) -> true ; Port = 3060 ),
	server_token(Options, SOpts),
	(   current_predicate(lps_http:lps_server/2)
	->  lps_http:lps_server(Port, SOpts),
	    ( SOpts == [] -> format('no token: every request is accepted~n', []) ; true ),
	    format('LPS2 IDE on http://localhost:~w/~n', [Port]),
	    format('press Ctrl-C to stop~n', []),
	    thread_get_message(_)
	;   format(user_error, 'src/edges/lps_http.pl is not loaded~n', []), halt(2)
	).
run_command(C, _, _) :-
	format(user_error, 'unknown command: ~w~n', [C]),
	usage, halt(2).

input_syntax_option(syntax(_)).

%	The dump is text; the surface writer wants terms. Reading it back with the
%	operator table in scope is the same path the internal reader takes.
internal_terms_of(Text, Terms) :-
	setup_call_cleanup(open_string(Text, In),
			   read_internal_terms(In, Terms),
			   close(In)).

read_internal_terms(In, Terms) :-
	read_term(In, T, [module(lps_ops)]),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [T|Rest], read_internal_terms(In, Rest)
	).


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
	compile_source(Syntax, File, Options, Program, Diags0),
	%  `--sandbox` (or LPS_SANDBOX=1) refuses a program whose Prolog reaches
	%  the machine — the check the server makes by default. Off here, because
	%  this is your file and the corpus predates the idea.
	(   sandbox_enabled(Options, true)
	->  catch(sandbox_check(Program, SDiags), _, SDiags = []),
	    append(Diags0, SDiags, Diags)
	;   Diags = Diags0
	),
	forall(member(D, Diags),
	       ( format_diag(D, A), format(user_error, '~w~n', [A]) )),
	(   diags_ok(Diags)
	->  true
	;   halt(1)
	).

%	Planner options given on the command line travel with the compile, so
%	`--search bfs` overrides the program's own directive (lps_session.pl's
%	engine_options/2 merges them).
compile_source(Syntax, File, Options, Program, Diags) :-
	include(planner_flag, Options, Extra),
	Extra \== [], !,
	append([dc], Extra, CO),
	compile_with(Syntax, File, CO, Program, Diags).
compile_source(Syntax, File, _Options, Program, Diags) :-
	compile_with(Syntax, File, [dc], Program, Diags).

planner_flag(search(_)).
planner_flag(horizon(_)).
planner_flag(nodes(_)).

compile_with(le, File, CO, Program, Diags) :- !,
	lps_le_translate(File, Text, Prov, LeDiags),
	(   diags_ok(LeDiags)
	->  le_terms(Text, Prov, Terms0),
	    companion_terms(File, Extra, ExtraDiags),
	    append(Terms0, Extra, Terms),
	    lps_compile(terms(Terms), internal, CO, Program, CDiags),
	    append([LeDiags, ExtraDiags, CDiags], Diags)
	;   Program = none, Diags = LeDiags
	).
%	An Inform 7 source (docs/project/plans/InformPlan.md phase 4): its assertions become a
%	Logical English story on the library, translated as a buffer whose
%	include base is the library's directory; the descriptions are its
%	companion. The rule register arrives as diagnostics.
compile_with(inform, File, CO, Program, Diags) :- !,
	lps_inform:inform_to_le(File, LE, Companion, IDiags),
	lps_le_translate_text(LE, 'story.le', Text, Prov, LeDiags),
	(   diags_ok(LeDiags)
	->  lps_le_program_terms(Text, File, Prov, Companion, 'story.lps', Terms, ReadDiags),
	    lps_compile(terms(Terms), internal, CO, Program, CDiags),
	    append([IDiags, LeDiags, ReadDiags, CDiags], Diags)
	;   Program = none, append(IDiags, LeDiags, Diags)
	).
compile_with(Syntax, File, CO, Program, Diags) :-
	lps_compile(file(File), Syntax, CO, Program, Diags).

%!	companion_terms(+LEFile, -Terms, -Diags) is det.
%
%	`foo.le` and `foo.lps` compile together, `.le` first. That is the
%	documented escape hatch of docs/user/reference/le-for-lps.md §7: `display/2`,
%	Prolog escapes and real-time plumbing are not Logical English and gain
%	nothing from being written as if they were, so they go in a companion
%	file with the right editor mode and the right diagnostics — rather than
%	in an in-band block the LE editor cannot check.
%
%	This is the rule for a *file*, which is what the CLI has: the companion
%	is found on disk beside the document, and read with the include-aware
%	reader. `lps_le_companion_terms/4` is the same rule for a *buffer*, which
%	is what the IDE and the assistant have — there the caller says what the
%	companion is, because a browser has nothing to look beside the document
%	in. Change one and read the other.
companion_terms(LEFile, Terms, Diags) :-
	(   atom_concat(Base, '.le', LEFile),
	    atom_concat(Base, '.lps', Companion),
	    exists_file(Companion)
	->  legacy_to_internal(file(Companion), [dc], Terms, Diags)
	;   Terms = [], Diags = []
	).

%	Zip the provenance onto the terms read out of LE2's internal text, so
%	every diagnostic downstream reports an `.le` line and column rather
%	than a line of generated Prolog nobody wrote (docs/dev/le-lps-interface.md).
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
syntax_of(File, _, inform) :- ( sub_atom(File, _, _, 0, '.ni') ; sub_atom(File, _, _, 0, '.inform') ), !.
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
		 *	      PDDL		*
		 *******************************/

/* The plan, in PDDL's own plan format, and then the verdict from the
   independent simulator (§IV.5's oracle: it reads the PDDL, not our
   translation of it, so a bug in the translation cannot hide in the check). */
pddl_report(Domain, Problem, _S, Trace, Options) :-
	findall(Step,
		( member(stage(events, C, Items), Trace), Items \== [],
		  C > 1, Step = Items ),
		Plan),
	(   Plan == []
	->  format('no plan found~n', []), halt(1)
	;   length(Plan, N),
	    format('; plan for ~w (~w steps)~n', [Problem, N]),
	    forall(( nth1(I, Plan, Actions), member(A, Actions) ),
		   ( pddl_action_text(A, Text), J is I - 1, format('~w: ~w~n', [J, Text]) )),
	    lps_pddl:pddl_plan_valid(Domain, Problem, Plan, Verdict),
	    format('; VALIDATION: ~w~n', [Verdict]),
	    ( option(json, Options) -> true ; true ),
	    ( Verdict == valid -> true ; halt(1) )
	).

%	`--facts "fire(kitchen), sprinkler(kitchen, off)"` — the initial working
%	memory, since a DRL file does not carry one.
parse_fact_list(S, Facts) :-
	format(atom(A), '[~w]', [S]),
	catch(term_to_atom(Facts, A), _, Facts = []).

pddl_action_text(A, Text) :-
	A =.. [Name|Args],
	atomic_list_concat(Args, ' ', ArgText),
	( Args == [] -> format(atom(Text), '(~w)', [Name])
	; format(atom(Text), '(~w ~w)', [Name, ArgText]) ).

		 /*******************************
		 *	     play		*
		 *******************************/

write_text(File, Text) :-
	setup_call_cleanup(open(File, write, S, [encoding(utf8)]), write(S, Text), close(S)).

play_repl(Id) :-
	format('~n> ', []), flush_output,
	read_line_to_string(user_input, Line0),
	(   ( Line0 == end_of_file ; Line0 == "quit" ; Line0 == "q" )
	->  format('~n', [])
	;   normalize_space(string(Line), Line0),
	    (   Line == ""
	    ->	true
	    ;	Line == "why"
	    ->	lps_play:play_why(Id, last, Ls),
		( Ls == [] -> format('Nothing to explain yet.~n', []) ; true ),
		forall(member(L, Ls), format('~w~n', [L]))
	    ;	( Line == "commands" ; Line == "help" ; Line == "?" )
	    ->	lps_play:play_commands(Id, Cs),
		( Cs == [] -> format('Nothing can be done from here.~n', [])
		; format('You could:~n', []), forall(member(C, Cs), format('  ~w~n', [C.text])) )
	    ;	Line == "fork"
	    ->	lps_play:play_fork(Id, Id2),
		format('forked: this is now ~w (the other is ~w). `diff` compares them.~n', [Id2, Id]),
		play_repl(Id2)
	    ;	Line == "games"
	    ->	lps_play:play_list(Gs),
		forall(member(G, Gs), format('  ~w  turn ~w  ~w~n', [G.play, G.turn, G.parent]))
	    ;	string_concat("switch ", IdS, Line)
	    ->	atom_string(Id3, IdS),
		( lps_play:play_status(Id3, St3), St3.ok == true
		->  format('now ~w~n', [Id3]), play_repl(Id3)
		;   format('no such game: ~w~n', [Id3]) )
	    ;	Line == "diff"
	    ->	lps_play:play_status(Id, StD),
		(   lps_play:game(Id, GD), get_dict(parent, GD, Parent)
		->  lps_play:play_diff(Parent, Id, DL), forall(member(L, DL), format('~w~n', [L]))
		;   StD.ok == true, format('this game was not forked; `fork` first.~n', [])
		)
	    ;	string_concat("why ", QS, Line)
	    ->	catch(( term_string(Q, QS), lps_play:play_why(Id, Q, Ls),
			forall(member(L, Ls), format('~w~n', [L])) ),
		      E, ( print_message(error, E) ))
	    ;	lps_play:play_turn(Id, Line, R),
		(   R.ok \== true
		->  format('~w~n', [R.error])
		;   get_dict(understood, R, false)
		->  play_guessed(Id, Line, R)
		;   forall(member(L, R.lines), format('~w~n', [L]))
		)
	    ),
	    play_repl(Id)
	).

%	A line the parser did not understand: a model, if there is a key for
%	one, picks among the commands the story could take; the pick is played
%	as if typed. Without a key the parser's answer stands.
play_guessed(Id, Line, R) :-
	format('let me see if I understand...~n'), flush_output,
	lps_play:play_guess(Id, Line, Gs),
	( get_dict(note, Gs, Note), Note \== null -> format('(~w)~n', [Note]) ; true ),
	(   Gs.ok == true, Gs.available == true, Gs.command \== null
	->  format('(I take that as: ~w)~n', [Gs.command]),
	    lps_play:play_turn(Id, Gs.command, R2),
	    forall(member(L, R2.lines), format('~w~n', [L]))
	;   Gs.ok == true, Gs.available == true
	->  format('I really don''t understand that.~n')
	;   forall(member(L, R.lines), format('~w~n', [L]))
	).

		 /*******************************
		 *	   live sessions		*
		 *******************************/

live_repl(Id) :-
	lps_live:live_status(Id, S),
	forall(member(L, S.recent), format('  ~w~n', [L])),
	%  Only when it changes: a heartbeat every second is noise, and the
	%  interesting thing is that the number is moving at all.
	(   nb_current(lps_live_cycle, S.cycle)
	->  true
	;   nb_setval(lps_live_cycle, S.cycle),
	    format('[cycle ~w]~n', [S.cycle])
	),
	flush_output,
	(   S.status \== "running"
	->  format('session ended: ~w~n', [S.status])
	;   read_live_line(Line),
	    (	( Line == end_of_file ; Line == "stop" )
	    ->	lps_live:live_command(Id, stop), format('stopped~n', [])
	    ;	Line == ""
	    ->	live_repl(Id)
	    ;	Line == "pause"
	    ->	lps_live:live_command(Id, pause), live_repl(Id)
	    ;	Line == "resume"
	    ->	lps_live:live_command(Id, resume), live_repl(Id)
	    ;	lps_live:live_observe(Id, [Line], R),
		( R.ok == true -> true ; format('~w~n', [R.error]) ),
		live_repl(Id)
	    )
	).

%	A line, or nothing if none arrived within a second — so the log keeps
%	printing while the session runs and nobody is typing.
read_live_line(Line) :-
	(   wait_for_input([user_input], [user_input], 1)
	->  read_line_to_string(user_input, Line)
	;   Line = ""
	).

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
