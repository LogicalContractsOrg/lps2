/* lps_source.pl — reading program text (an *edge*, §I.2).

   The core compiles from terms. Turning a path into terms is I/O, so it lives
   out here, where I/O is allowed. That is not bookkeeping: it is what lets
   tools/lint_core.pl assert something true about `src/core/` rather than
   something aspirational, and it is why a session can be compiled from an
   editor buffer, an HTTP request body or a generated program with no file
   involved at all.

   `:- include(F)` is expanded here, mirroring psyntax:term_includer/5. The
   corpus relies on it: ten CLOUT_workshop programs pull in the engine's
   date_utils library that way, and the generated `_.P` files keep the
   directive rather than inlining it.
*/

:- module(lps_source, [
	lps_read_terms/3,        % +File, -Terms, -Diags
	lps_load_directive/4,    % +Module, +Origin, +Directive, -Diags
	lps_source_dir/1         % -Dir
	]).

:- use_module(library(lists)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').

%!	lps_read_terms(+File, -Terms, -Diags) is det.
%
%	Terms are `t(Term, Line)` pairs, so the compiler can attach provenance
%	(§I.3) without reading the file a second time.
lps_read_terms(File, Terms, Diags) :-
	(   exists_file(File)
	->  catch(( read_terms_from(File, [], Terms0) -> R = ok(Terms0) ; R = failed ),
		  E, R = error(E)),
	    (	R = ok(Terms)
	    ->	Diags = []
	    ;	Terms = [],
		format(atom(M), '~w: ~q', [File, R]),
		diag(error, read_failed, unknown, M, D),
		Diags = [D]
	    )
	;   format(atom(M), 'no such file: ~w', [File]),
	    diag(error, no_such_file, unknown, M, D),
	    Terms = [], Diags = [D]
	).

/* Two passes, and the second one almost never runs.

   Pass 1 reads with the operator table of this module, which is the LPS table
   and nothing else — no program can change how a later program parses.

   A program that imports an operator-bearing library, though, cannot be read
   that way: `X #> 2` after `:- use_module(library(clpfd))` is a syntax error
   until clpfd's operators are in scope, and putting them in scope *here* would
   leak them into every subsequent program. So pass 2 reads the same file in a
   scratch module that inherits the LPS table, applying `:- op/3` and
   `:- use_module/1` as it meets them. The scratch module is thrown away; only
   the terms come back.

   Retrying on a syntax error rather than pre-scanning for imports means the
   common path is byte-for-byte what it was, and the cost of the rare path is
   paid only by the programs that need it.
*/
read_terms_from(File, Included, Terms) :-
	(   catch(read_pass(File, Included, lps_source, Terms0), _, fail)
	->  Terms = Terms0
	;   scratch_module(M),
	    %  Any exception from the second pass propagates: it is the one the
	    %  user should see, since the retry has given the file every chance.
	    read_pass(File, Included, M, Terms)
	).

read_pass(File, Included, Module, Terms) :-
	setup_call_cleanup(
	    open(File, read, S, [encoding(utf8)]),
	    read_terms_stream(S, File, Included, Module, Terms),
	    close(S)).

:- dynamic scratch_counter/1.
scratch_counter(0).

%	A fresh module inheriting core/lps_ops, so that read_term/3 sees the LPS
%	operators plus whatever the program imports, and nothing sees them after.
scratch_module(M) :-
	retract(scratch_counter(N)), N1 is N + 1, assertz(scratch_counter(N1)),
	format(atom(M), 'lps_read_scratch_~w', [N1]),
	dynamic(M:'$lps_reader'/0),
	add_import_module(M, lps_ops, start).

read_terms_stream(S, File, Included, Module, Terms) :-
	line_count(S, Line0),
	Line is Line0 + 1,
	%  read_term/3 takes operators from the module named here, not from the
	%  caller. Without it the LPS table (core/lps_ops.pl) is invisible and a
	%  generated `_.P` file — which writes `actions [row(_,_)].` and
	%  `holds(not loc(goat,_), T)` — does not parse.
	read_term(S, T, [variable_names(_), module(Module)]),
	(   T == end_of_file
	->  Terms = []
	;   T = (:- include(Spec))
	->  resolve_include(Spec, File, Path),
	    (   memberchk(Path, Included)
	    ->  Sub = []                       % already pulled in; skip silently
	    ;   length(Included, N), N < 6,
		catch(read_pass(Path, [Path|Included], Module, Sub0), _, fail)
	    ->  Sub = Sub0
	    ;   Sub = []
	    ),
	    read_terms_stream(S, File, Included, Module, More),
	    append(Sub, More, Terms)
	;   ( Module \== lps_source -> apply_reader_directive(Module, File, T) ; true ),
	    Terms = [t(T, Line)|More],
	    read_terms_stream(S, File, Included, Module, More)
	).

%	On the scratch pass only: make the operators a directive brings into
%	scope available to the rest of the file. Failures are ignored here — the
%	directive is applied again, and reported, when the program is compiled
%	(lps_load_directive/4).
apply_reader_directive(M, _File, (:- op(P, T, N))) :- !,
	catch(M:op(P, T, N), _, true).
apply_reader_directive(M, File, (:- G)) :-
	load_goal(G, _, _, _), !,
	catch(lps_load_directive(M, File, G, _), _, true).
apply_reader_directive(_, _, _).

%	`system(Rel)` is upstream's file_search_path for engine/system, where
%	date_utils.pl lives.
%	`example(Rel)` is upstream's other file_search_path, pointing at
%	examples/CLOUT_workshop, where the SzaboLanguage contracts keep their
%	shared base program.
resolve_include(example(Rel), _From, Path) :- !,
	(   example_dir(Dir),
	    atomic_list_concat([Dir, '/', Rel], Path),
	    exists_file(Path)
	->  true
	;   Path = Rel
	).
resolve_include(system(Rel), _From, Path) :- !,
	(   system_dir(Dir),
	    atomic_list_concat([Dir, '/', Rel], Path),
	    exists_file(Path)
	->  true
	;   Path = Rel
	).
resolve_include(Rel, From, Path) :-
	(   is_absolute_file_name(Rel)
	->  Path = Rel
	;   file_directory_name(From, Dir),
	    atomic_list_concat([Dir, '/', Rel], Path)
	).

example_dir(Dir) :-
	lps_source_dir(Root),
	atomic_list_concat([Root, '/legacy_lps1/examples/CLOUT_workshop'], Dir).

system_dir(Dir) :-
	lps_source_dir(Root),
	atomic_list_concat([Root, '/src/system'], Dir).
system_dir(Dir) :-
	lps_source_dir(Root),
	atomic_list_concat([Root, '/legacy_lps1/engine/system'], Dir).

		 /*******************************
		 *	  load directives	*
		 *******************************/

/* A program may import Prolog modules:

     :- use_module(library(clpfd)).
     :- use_module(helpers).             % relative to the program's own file

   Loading a module is file I/O, so the *decision* to honour a directive is made
   in the core (which knows which ones are safe) and the loading happens here.
   The core reaches this predicate by the same late-binding test it uses for
   lps_read_terms/3, so a core-only deployment simply has no loadable
   directives rather than a missing dependency.

   Relative specifications resolve against the directory of the program's own
   file, not the working directory: `use_module/1` normally resolves against the
   file being *consulted*, and we are not consulting one — the program's clauses
   are asserted into a private module.
*/

%!	lps_load_directive(+Module, +Origin, +Directive, -Diags) is det.
lps_load_directive(Module, Origin, Goal, Diags) :-
	(   load_goal(Goal, Pred, Spec, Rest)
	->  (   resolve_load_spec(Spec, Origin, Resolved)
	    ->	Goal2 =.. [Pred, Resolved|Rest],
		load_call(Module, Goal, Goal2, Diags)
	    ;	unresolved(Goal, Spec, Diags)
	    )
	;   Diags = []
	).

load_goal(use_module(S),    use_module,    S, []).
load_goal(use_module(S, I), use_module,    S, [I]).
load_goal(ensure_loaded(S), ensure_loaded, S, []).

load_call(Module, Goal, Goal2, Diags) :-
	catch(( Module:Goal2 -> Diags = [] ; failed_diag(Goal, failed, Diags) ),
	      E,
	      failed_diag(Goal, E, Diags)).

failed_diag(Goal, Why, [D]) :-
	format(atom(M), 'could not load ~q: ~w', [Goal, Why]),
	diag(warning, load_directive_failed, unknown, M, D).

unresolved(Goal, Spec, [D]) :-
	format(atom(M), 'could not resolve ~q in ~q', [Spec, Goal]),
	diag(warning, load_directive_unresolved, unknown, M, D).

%	library(foo) and other alias(Rel) forms are left to SWI's own search
%	path. A bare atom or a relative path is resolved against the program.
resolve_load_spec(Spec, _Origin, Spec) :-
	compound(Spec), Spec =.. [_Alias, _Rel], !.
resolve_load_spec(Spec, _Origin, Spec) :-
	is_list(Spec), !.
resolve_load_spec(Spec, Origin, Resolved) :-
	atom(Spec),
	(   is_absolute_file_name(Spec)
	->  Resolved = Spec
	;   atom(Origin), Origin \== buffer, Origin \== unknown
	->  file_directory_name(Origin, Dir),
	    atomic_list_concat([Dir, '/', Spec], Resolved)
	;   Resolved = Spec
	).

%!	lps_source_dir(-Dir) is det.
lps_source_dir(Root) :-
	module_property(lps_source, file(F)),
	file_directory_name(F, EdgeDir),
	file_directory_name(EdgeDir, SrcDir),
	file_directory_name(SrcDir, Root).
