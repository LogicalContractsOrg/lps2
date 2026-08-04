/* bench.pl — the M5 measurements.

   §I.6 predicted a dual-backend state store: a fast destructive one for the
   committed trunk and a persistent one for hypothetical branches, on the
   assumption that the store would be a dynamic predicate and forking would
   therefore be expensive.

   LPS2 does not have that problem, because §I.2.1's decision went further
   than §I.6 assumed: a *session* is an immutable term, so the state is a
   value and `lps_session_fork/2` is a unification. There is one backend, and
   there is nothing for a fork to copy.

   What is worth measuring, and what this tool measures:

     fork      the cost of lps_session_fork/2, against session size
     step      cycles per second on the corpus, for the regression budget
     diverge   that two forks of one session really are independent

   Usage:
     ./myswipl.sh -q -g "consult('tools/bench.pl')" -g "bench:main" -t halt
*/

:- module(bench, [ main/0, main/1, bench_fork/2, bench_program/3 ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_program').
:- use_module('../conformance/corpus').

main :- main([]).

main(_Argv) :-
	fork_benchmark,
	divergence_check,
	step_benchmark.

		 /*******************************
		 *	   fork cost		*
		 *******************************/

fork_benchmark :-
	format('~n=== fork cost ===~n', []),
	format('~w~t~34|~w~t~48|~w~n', ['program', 'cycles run', 'us/fork']),
	forall(member(Slug, ['goat.pl', 'CLOUT_workshop_diningPhilosophers.pl',
			     'CLOUT_workshop_bubbleSort.pl']),
	       ( entry_program(Slug, P)
	       ->  bench_fork(P, Report), print_fork(Slug, Report)
	       ;   true
	       )).

print_fork(Slug, fork(Cycles, Micros)) :-
	format('~w~t~34|~w~t~48|~2f~n', [Slug, Cycles, Micros]).

%!	bench_fork(+Program, -Report) is det.
%
%	Fork a session that has been run for a while, so the session term is as
%	big as it is going to get. If forking were O(size) this is where it
%	would show.
bench_fork(P, fork(Cycles, Micros)) :-
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _),
	lps_session_time(S, Cycles),
	N = 10000,
	statistics(walltime, _),
	forall(between(1, N, _), ( lps_session_fork(S, S2), nonvar(S2) )),
	statistics(walltime, [_, Ms]),
	Micros is Ms * 1000 / N.

		 /*******************************
		 *	  independence		*
		 *******************************/

%	A fork that shared anything with its parent would show up here: the two
%	branches see different events and must reach different states.
divergence_check :-
	format('~n=== fork independence ===~n', []),
	(   entry_program('forTesting_two_initiate.pl', P)
	->  lps_session_new(P, [dc], S0),
	    lps_session_step(S0, S1, _),
	    lps_session_fork(S1, A0),
	    lps_session_fork(S1, B0),
	    lps_session_run(A0, cycles(3), A, _),
	    lps_session_run(B0, cycles(1), B, _),
	    lps_session_time(A, TA), lps_session_time(B, TB),
	    lps_session_time(S1, TS),
	    format('  parent at cycle ~w; branches at ~w and ~w~n', [TS, TA, TB]),
	    (	TA =\= TB, TS =:= 2
	    ->	format('  independent: yes~n', [])
	    ;	format('  independent: NO~n', [])
	    )
	;   format('  (example not found)~n', [])
	).

		 /*******************************
		 *	   step throughput	*
		 *******************************/

step_benchmark :-
	format('~n=== step throughput ===~n', []),
	format('~w~t~46|~w~t~56|~w~n', ['program', 'cycles', 'cycles/s']),
	corpus_entries([main], Entries),
	forall(( member(entry(Slug, _, PFile, _), Entries), bench_slug(Slug) ),
	       ( bench_program(PFile, Cycles, Seconds)
	       ->  ( Seconds > 0 -> Rate is Cycles / Seconds ; Rate = 0 ),
		   format('~w~t~46|~w~t~56|~0f~n', [Slug, Cycles, Rate])
	       ;   format('~w~t~46|(failed)~n', [Slug])
	       )).

%	A representative handful rather than the whole corpus: this is a
%	regression budget, not a profile.
bench_slug('goat.pl').
bench_slug('CLOUT_workshop_diningPhilosophers.pl').
bench_slug('CLOUT_workshop_bubbleSort.pl').
bench_slug('tictactoe.pl').
bench_slug('CLOUT_workshop_life.pl').

bench_program(PFile, Cycles, Seconds) :-
	lps_compile(file(PFile), internal, [dc], P, D),
	lps_diag:diags_ok(D),
	statistics(walltime, _),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _),
	statistics(walltime, [_, Ms]),
	Seconds is Ms / 1000,
	lps_session_time(S, Cycles).

entry_program(Slug, P) :-
	corpus_entries([main], Entries),
	member(entry(Slug, _, PFile, _), Entries), !,
	lps_compile(file(PFile), internal, [dc], P, D),
	lps_diag:diags_ok(D).
