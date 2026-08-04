/* lps_wasm.pl — "Deploy as WASM" (M11, proof of concept).
 *
 * §I.0 deferred WASM but kept the guard that makes it possible: nothing in
 * src/core/ touches threads, sockets, the clock, foreign code or files, and
 * tools/lint_core.pl has been enforcing that since M1. This is the milestone
 * where that guard gets cashed in — the question "is the core actually
 * loadable in a browser?" stops being a claim and becomes a page you can open.
 *
 * What it produces: a **self-contained HTML page** carrying one LPS program,
 * the engine's Prolog sources inlined as strings, and a swipl-wasm loader. The
 * page runs the program in the browser with no server of any kind, and prints
 * the trace. No `/lpsapi`, no SWI-Prolog installation, no network after the
 * page and its runtime have loaded.
 *
 * The honest limits of the proof:
 *
 *   * Only the **core plus the syntax layer** is shipped. The edges — HTTP,
 *     the assistant, live sessions, the LE bridge — are not, and could not be:
 *     they are the parts that touch the world.
 *   * The page loads swipl-wasm's runtime (`swipl-web.js`, `.wasm`, `.data`)
 *     from wherever it was served. Inlining ~7 MB of base64 would make one
 *     file that works from a memory stick; serving it is what a real
 *     deployment does, and either can be chosen at generation time.
 *   * Everything is synchronous and single-threaded, which is exactly what the
 *     core already was.
 */

:- module(lps_wasm, [
	wasm_bundle/3,           % +ProgramText, +Options, -Html
	wasm_sources/1           % -List of file(Path, Text)
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).

%!	wasm_sources(-Files) is det.
%
%	The engine, in load order. `src/lps.pl` itself is not used: it pulls in
%	the edges, and the edges are the half that cannot run here.
wasm_sources(Files) :-
	lps_root(Root),
	findall(file(Rel, Text),
		( member(Rel, ['src/core/lps_ops.pl',
			       'src/core/lps_diag.pl',
			       'src/core/lps_terms.pl',
			       'src/core/lps_time.pl',
			       'src/core/lps_program.pl',
			       'src/core/lps_builtins.pl',
			       'src/core/lps_store.pl',
			       'src/core/lps_query.pl',
			       'src/core/lps_resolve.pl',
			       'src/core/lps_cycle.pl',
			       'src/core/lps_planner.pl',
			       'src/core/lps_explain.pl',
			       'src/core/lps_session.pl',
			       'src/syntax/lps_legacy_syntax.pl',
			       'src/syntax/lps_internal_syntax.pl',
			       'src/edges/lps_wasm_boot.pl']),
		  atomic_list_concat([Root, '/', Rel], Path),
		  exists_file(Path),
		  read_file_to_string(Path, Text, [encoding(utf8)]) ),
		Files).

lps_root(Root) :-
	module_property(lps_wasm, file(F)),
	file_directory_name(F, Dir), file_directory_name(Dir, Src),
	file_directory_name(Src, Root).

%!	wasm_bundle(+ProgramText, +Options, -Html) is det.
%
%	Options: `title(T)`, `runtime(URL)` — where swipl-web.js is served from.
%
%	The page is a template with four holes rather than a format/3 string:
%	generating HTML-with-JavaScript out of Prolog quoting is a way to spend an
%	afternoon on backslashes, and the template can be opened in a browser on
%	its own.
wasm_bundle(ProgramText, Options, Html) :-
	wasm_sources(Files),
	( memberchk(title(Title0), Options) -> true ; Title0 = "an LPS program" ),
	( memberchk(runtime(Rt), Options) -> true ; Rt = '/assets/swipl/swipl-web.js' ),
	maplist(source_entry, Files, Entries),
	atomic_list_concat(Entries, ',\n ', Joined),
	atomic_list_concat(['[\n ', Joined, '\n]'], SourcesJs),
	js_string(ProgramText, ProgramJs),
	html_escape(Title0, Title),
	template(T0),
	replace_all(T0, '__SOURCES__', SourcesJs, T1),
	replace_all(T1, '__PROGRAM__', ProgramJs, T2),
	replace_all(T2, '__RUNTIME__', Rt, T3),
	replace_all(T3, '__TITLE__', Title, Html).

template(Text) :-
	lps_root(Root),
	atomic_list_concat([Root, '/src/edges/wasm_template.html'], Path),
	read_file_to_string(Path, Text, [encoding(utf8)]).

replace_all(In, From, To, Out) :-
	atomic_list_concat(Parts, From, In),
	atomic_list_concat(Parts, To, Out).

html_escape(S, Out) :-
	atom_string(A, S),
	atomic_list_concat(P1, '&', A), atomic_list_concat(P1, '&amp;', A1),
	atomic_list_concat(P2, '<', A1), atomic_list_concat(P2, '&lt;', A2),
	atomic_list_concat(P3, '>', A2), atomic_list_concat(P3, '&gt;', Out).

source_entry(file(Path, Text), Entry) :-
	js_string(Path, P),
	js_string(Text, T),
	format(atom(Entry), '[~w, ~w]', [P, T]).

%	JavaScript string literals. `<` and `>` are escaped as well as the
%	obvious characters: a program containing `</script>` would otherwise end
%	the page's own script block, which is the classic way to turn a source
%	listing into a security hole.
js_string(Text, Out) :-
	with_output_to(atom(Out), write_js_string(Text)).

write_js_string(Text) :-
	atom_string(A, Text), atom_codes(A, Codes),
	write('"'),
	forall(member(C, Codes), js_char(C)),
	write('"').

js_char(0'") :- !, write('\\"').
js_char(0'\\) :- !, write('\\\\').
js_char(0'\n) :- !, write('\\n').
js_char(0'\r) :- !, write('\\r').
js_char(0'\t) :- !, write('\\t').
js_char(0'<) :- !, write('\\u003c').
js_char(0'>) :- !, write('\\u003e').
js_char(C) :- C < 32, !, format('\\u~|~`0t~16r~4+', [C]).
js_char(C) :- char_code(Ch, C), write(Ch).
