/* lps_wasm_boot.pl — what runs a program inside the browser (M11).
 *
 * The core compiles from *terms*; turning a path into terms is I/O and lives
 * in src/edges/ (lps_source.pl). In the browser there is no edges layer — no
 * HTTP, no assistant, no live sessions — but there is still a file system, the
 * virtual one swipl-wasm provides, so this is the one small piece of edge that
 * the WASM bundle carries: read the program, compile it, run it, print the
 * trace.
 *
 * It is deliberately not lps_source.pl: that file does two-pass reading with a
 * scratch module for operator-bearing imports, and a page that runs one
 * program does not need any of it.
 */

:- module(lps_wasm_boot, [wasm_run/1]).

:- use_module(library(lists)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').
:- use_module('../core/lps_session').

%!	wasm_run(+File) is det.
wasm_run(File) :-
	catch(wasm_run_(File), E, format('error: ~q~n', [E])).

wasm_run_(File) :-
	read_program(File, Terms),
	lps_compile(terms(Terms), legacy, [dc], Program, Diags),
	forall(member(D, Diags), ( format_diag(D, A), format('~w~n', [A]) )),
	(   diags_ok(Diags)
	->  lps_session_new(Program, [dc], S0),
	    lps_session_run(S0, end, S, Trace),
	    print_trace(Trace),
	    lps_session_status(S, St),
	    format('~n~w~n', [St])
	;   format('~nthe program did not compile~n', [])
	).

%	The operator table has to be in scope for the read, which is what
%	`module(lps_ops)` does: without it `actions [row(_,_)].` is a syntax
%	error and `holds(not loc(goat,_), T)` does not parse.
read_program(File, Terms) :-
	setup_call_cleanup(open(File, read, S, [encoding(utf8)]),
			   read_terms_(S, Terms),
			   close(S)).

read_terms_(S, Terms) :-
	read_term(S, T, [module(lps_ops), variable_names(_)]),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [T|Rest], read_terms_(S, Rest)
	).

print_trace(Trace) :-
	forall(( member(stage(Stage, C, Items), Trace), Items \== [] ),
	       format('~w/~w~t~14| ~q~n', [Stage, C, Items])).
