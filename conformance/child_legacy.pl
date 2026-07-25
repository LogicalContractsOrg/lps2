/* child_legacy.pl — one legacy-engine run, in its own process.

   Usage (see conformance/adapter_legacy.pl, which drives this):

     swipl conformance/child_legacy.pl EngineDir Mode File StatusFile TimeLimit Opt...

   Mode is
     generate : translate surface syntax File (e.g. foo.pl) into foo.pl_.P
     run      : interpreter:go(File, [make_test|Opts]) — File is an internal-syntax
                `_.P` file; the engine writes File.lpst next to it, which is the
                trace the harness reads back.
     verify   : interpreter:go(File, [run_test|Opts]) — the legacy engine checks
                itself against the golden File.lpst that the harness placed next to
                the program. Used only to cross-validate our own comparison against
                upstream's; it adds `failed(...)` terms to the status file.

   The status file receives one term:  result(success|failed|error(E)|timeout).
   `failed` is normal and expected for programs whose golden trace records
   lps_test_result_item(end,-1,failure).

   Everything the engine prints goes to stdout/stderr, which the parent redirects
   to a log file. Nothing is printed here except on catastrophic failure.
*/

:- initialization(main, main).

main(Argv) :-
	Argv = [EngineDir, Mode, File, StatusFile, TimeLimitA | OptionAtoms],
	atom_number(TimeLimitA, TimeLimit),
	maplist(atom_to_term_, OptionAtoms, Options),
	atomic_list_concat([EngineDir, '/utils/psyntax.P'], Psyntax),
	load_engine(Psyntax),
	run(Mode, File, TimeLimit, Options, Result),
	extra_terms(Mode, Extra),
	save_status(StatusFile, [result(Result)|Extra]).

atom_to_term_(A, T) :- term_to_atom(T, A).

load_engine(Psyntax) :-
	catch(consult(Psyntax), E,
	      ( print_message(error, E),
		halt(4) )).

run(generate, File, TimeLimit, _Options, Result) :- !,
	guarded(TimeLimit, psyntax:generate_file(File), Result).
run(run, File, TimeLimit, Options, Result) :- !,
	guarded(TimeLimit, interpreter:go(File, [make_test|Options]), Result).
run(verify, File, TimeLimit, Options, Result) :-
	guarded(TimeLimit, interpreter:go(File, [run_test|Options]), Result).

%	After a `verify` run, upstream's own criterion (interpreter:do_test_suite/3) is
%	"go/2 succeeded and no lps_failed_test/2 was recorded".
extra_terms(verify, [failed_tests(N, Fs)]) :- !,
	catch(findall(f(A,B), db:lps_failed_test(A,B), Fs0), _, Fs0 = [unavailable]),
	length(Fs0, N),
	first_n(3, Fs0, Fs).
extra_terms(_, []).

first_n(0, _, []) :- !.
first_n(_, [], []) :- !.
first_n(N, [X|Xs], [X|Ys]) :- N1 is N-1, first_n(N1, Xs, Ys).

guarded(TimeLimit, Goal, Result) :-
	catch(
	    call_with_time_limit(TimeLimit,
		( catch(Goal, Inner, true)
		-> ( var(Inner) -> Result = success ; Result = error(Inner) )
		;  Result = failed )),
	    Outer,
	    ( Outer == time_limit_exceeded
	    -> Result = timeout
	    ;  Result = error(Outer) )).

save_status(StatusFile, Terms) :-
	setup_call_cleanup(
	    open(StatusFile, write, S),
	    forall(member(T, Terms),
		   \+ \+ ( numbervars(T, 0, _),
			   write_term(S, T, [quoted(true), numbervars(true)]),
			   write(S, '.'), nl(S) )),
	    close(S)).
