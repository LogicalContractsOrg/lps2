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

read_terms_from(File, Included, Terms) :-
	setup_call_cleanup(
	    open(File, read, S, [encoding(utf8)]),
	    read_terms_stream(S, File, Included, Terms),
	    close(S)).

read_terms_stream(S, File, Included, Terms) :-
	line_count(S, Line0),
	Line is Line0 + 1,
	%  read_term/3 takes operators from the module named here, not from the
	%  caller. Without it the LPS table (core/lps_ops.pl) is invisible and a
	%  generated `_.P` file — which writes `actions [row(_,_)].` and
	%  `holds(not loc(goat,_), T)` — does not parse.
	read_term(S, T, [variable_names(_), module(lps_source)]),
	(   T == end_of_file
	->  Terms = []
	;   T = (:- include(Spec))
	->  resolve_include(Spec, File, Path),
	    (   memberchk(Path, Included)
	    ->  Sub = []                       % already pulled in; skip silently
	    ;   length(Included, N), N < 6,
		catch(read_terms_from(Path, [Path|Included], Sub0), _, fail)
	    ->  Sub = Sub0
	    ;   Sub = []
	    ),
	    read_terms_stream(S, File, Included, More),
	    append(Sub, More, Terms)
	;   Terms = [t(T, Line)|More],
	    read_terms_stream(S, File, Included, More)
	).

%	`system(Rel)` is upstream's file_search_path for engine/system, where
%	date_utils.pl lives.
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

system_dir(Dir) :-
	lps_source_dir(Root),
	atomic_list_concat([Root, '/src/system'], Dir).
system_dir(Dir) :-
	lps_source_dir(Root),
	atomic_list_concat([Root, '/legacy_lps1/engine/system'], Dir).

%!	lps_source_dir(-Dir) is det.
lps_source_dir(Root) :-
	module_property(lps_source, file(F)),
	file_directory_name(F, EdgeDir),
	file_directory_name(EdgeDir, SrcDir),
	file_directory_name(SrcDir, Root).
