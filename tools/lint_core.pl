/* lint_core.pl — the core-purity lint (§I.2.4).

   > The core is a package with a CI lint failing the build on references to
   > `thread_*`, `message_queue_*`, `mutex_*`, HTTP libraries, sockets,
   > `process_create`, `shell`, `get_time`, or foreign predicates.

   That is the rule, implemented literally, plus two additions the plan's
   reasoning implies: `random*` (a core that can produce two different traces
   from the same session is not replayable) and file/stream I/O (reading a
   program is an edge's job — src/edges/lps_source.pl — precisely so that this
   check can be true rather than aspirational).

   The rule is about the *core package only*. Edges may use anything: the HTTP
   server may be threaded, the CLI may read the clock, adapters may call
   foreign libraries. The lint exists to keep the boundary honest — and, as a
   side effect, to keep the WASM option alive at zero ongoing cost (§I.0).

   Two things it deliberately does not catch, both noted here so nobody
   mistakes silence for a guarantee:

     - `p_call/2` calls the *program's* Prolog, which may do anything. That is
       the program's business, not the engine's.
     - b_setval/nb_setval are permitted and confined to core/lps_store.pl.
       They are process-local, deterministic and undone by backtracking, so
       replay and forking still hold; see that file's header for why the
       engine cannot be written without them.

   Usage:
     ./myswipl.sh -q -g "consult('tools/lint_core.pl')" -g "lint_core:main" -t halt
*/

:- module(lint_core, [ main/0, lint_core/2 ]).

:- use_module(library(lists)).
:- use_module(library(apply)).

%!	forbidden(?Pattern, ?Why) is nondet.
forbidden("thread_",         'threads').
forbidden("message_queue_",  'message queues').
forbidden("mutex_",          'mutexes').
forbidden("library(http",    'HTTP').
forbidden("tcp_socket",      'sockets').
forbidden("udp_socket",      'sockets').
forbidden("process_create",  'subprocesses').
forbidden("shell(",          'the shell').
forbidden("get_time(",       'the wall clock (§I.2.3: time is injected)').
forbidden("use_foreign_library", 'foreign code').
forbidden("load_foreign_library", 'foreign code').
forbidden("random",          'nondeterminism (breaks deterministic replay)').
forbidden("open(",           'file I/O (belongs in src/edges/)').
forbidden("see(",            'file I/O (belongs in src/edges/)').
forbidden("tell(",           'file I/O (belongs in src/edges/)').
forbidden("read_term(",      'file I/O (belongs in src/edges/)').
forbidden("exists_file(",    'file I/O (belongs in src/edges/)').

%	One documented exception, and it is not a hole: upstream's
%	`option(debug)` tracing hook, which writes nothing unless a caller asks
%	for it and is the only practical way to see why a goal took the branch
%	it took.
allowed_exception('lps_resolve.pl', "format(user_error").

main :-
	lint_core('src/core', Violations),
	(   Violations == []
	->  format('core purity: clean~n', []),
	    halt(0)
	;   length(Violations, N),
	    format('core purity: ~w violation(s)~n', [N]),
	    forall(member(v(File, Line, Pattern, Why, Text), Violations),
		   format('  ~w:~w  ~w  (~w)~n    ~w~n', [File, Line, Pattern, Why, Text])),
	    halt(1)
	).

%!	lint_core(+Dir, -Violations) is det.
lint_core(Dir, Violations) :-
	findall(F, core_file(Dir, F), Files),
	findall(V, ( member(F, Files), violation(F, V) ), Violations).

core_file(Dir, Path) :-
	exists_directory(Dir),
	directory_files(Dir, Entries),
	member(E, Entries),
	atom_concat(_, '.pl', E),
	atomic_list_concat([Dir, '/', E], Path).

violation(File, v(Base, Line, Pattern, Why, Text)) :-
	file_base_name(File, Base),
	read_file_to_string(File, S, [encoding(utf8)]),
	split_string(S, "\n", "", Lines),
	nth1(Line, Lines, Text0),
	\+ comment_line(Text0),
	forbidden(Pattern, Why),
	sub_string(Text0, _, _, _, Pattern),
	\+ ( allowed_exception(Base, Pattern2), sub_string(Text0, _, _, _, Pattern2) ),
	string_concat(Text1, "", Text0), Text = Text1.

%	A mention in a comment is documentation, not a dependency.
comment_line(Line) :-
	normalize_space(string(S), Line),
	( sub_string(S, 0, 1, _, "%") ; sub_string(S, 0, 1, _, "*") ; S == "" ).
