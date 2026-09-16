/* examples_test.pl — regression tests for LPS2's own examples.

   The corpus in legacy_lps1/ tests conformance with the old engine. This tests
   the things LPS2 adds, which by definition have no legacy golden:
   `examples/start/goat_declarative.pl` is the §I.7.3 program, and its trace is
   compared with `examples/<name>.lpst` using exactly the §0.2 contract — the
   same `lpst_compare/3` the conformance harness uses, so a planned program's
   trace is held to the same standard as a hand-written one. That is §I.7.5's
   whole point: the planner produces a plan, the *ordinary cycle* executes it,
   and what comes out is an ordinary LPS trace.

   Regenerate a golden with:
     ./lps run examples/NAME.pl --quiet --trace examples/NAME.pl.lpst

   Usage:
     ./myswipl.sh -q -g "consult('tools/examples_test.pl')" -g "ex:main" -t halt
*/

:- module(ex, [ main/0, check/2 ]).

:- use_module(library(lists)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_diag').
:- use_module('../src/syntax/lps_internal_syntax').
:- use_module('../conformance/lpst').

main :-
	findall(E, example(E), Examples),
	maplist(check, Examples, Verdicts),
	include(==(pass), Verdicts, Passes),
	length(Passes, NP), length(Verdicts, N),
	format('~n=== examples: ~w/~w ===~n', [NP, N]),
	( NP =:= N -> true ; halt(1) ).

example('start/goat_declarative.pl').

check(Name, Verdict) :-
	root(Root),
	atomic_list_concat([Root, '/examples/', Name], File),
	atomic_list_concat([File, '.lpst'], GoldenFile),
	(   exists_file(GoldenFile)
	->  lps_run(file(File), legacy, [dc], run(Outcome, Trace, Diags, _)),
	    (	diags_ok(Diags)
	    ->	trace_verdict(Trace, Outcome, GoldenFile, Verdict)
	    ;	Verdict = compile_errors
	    )
	;   Verdict = no_golden
	),
	format('~w~t~40| ~w~n', [Name, Verdict]).

trace_verdict(Trace, Outcome, GoldenFile, Verdict) :-
	root(Root),
	atomic_list_concat([Root, '/build/examples'], Dir),
	make_directory_path_(Dir),
	atomic_list_concat([Dir, '/actual.lpst'], Actual),
	write_lpst(Actual, Trace, [dc], Outcome),
	lpst_read(Actual, A),
	lpst_read(GoldenFile, G),
	lpst_compare(A, G, verdict(_, Strict, Failures)),
	(   Strict == pass
	->  Verdict = pass
	;   first_n(2, Failures, Shown), Verdict = fail(Shown)
	).

make_directory_path_(Dir) :- ( exists_directory(Dir) -> true ; make_directory_path(Dir) ).

first_n(0, _, []) :- !.
first_n(_, [], []) :- !.
first_n(N, [X|Xs], [X|Ys]) :- N1 is N - 1, first_n(N1, Xs, Ys).

root(Root) :-
	module_property(ex, file(F)),
	file_directory_name(F, ToolsDir),
	file_directory_name(ToolsDir, Root).
