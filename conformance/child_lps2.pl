/* child_lps2.pl — one LPS(2) run, in its own process.

   The counterpart of child_legacy.pl, and deliberately the same interface, so
   runner.pl can point either engine at the same corpus entry and compare the
   two `.lpst` files with the same code (§I.1.1: the harness is independent of
   both engines).

     swipl conformance/child_lps2.pl Root Mode File StatusFile TimeLimit Opt...

   Mode is
     run     : compile File (an internal-syntax `_.P`) and run it to
	       termination, writing File.lpst — the trace the harness reads back
     legacy  : same, but File is *surface* syntax and goes through the §I.4
	       translator first
     dump    : compile File and write its internal form to File.dump, for the
	       M2 round-trip gate

   Subprocess isolation is not paranoia here: a program may call arbitrary
   Prolog, and one corpus entry's `halt/0` should not take the suite with it.
*/

:- initialization(main, main).

main(Argv) :-
	Argv = [Root, Mode, File, StatusFile, TimeLimitA | OptionAtoms],
	atom_number(TimeLimitA, TimeLimit),
	maplist(atom_to_term_, OptionAtoms, Options),
	load_engine(Root),
	run(Mode, File, TimeLimit, Options, Result),
	save_status(StatusFile, [result(Result)]).

atom_to_term_(A, T) :- term_to_atom(T, A).

load_engine(Root) :-
	atomic_list_concat([Root, '/src/lps.pl'], Loader),
	catch(consult(Loader), E, ( print_message(error, E), halt(4) )).

run(run, File, TimeLimit, Options, Result) :- !,
	go(File, internal, TimeLimit, Options, Result).
run(legacy, File, TimeLimit, Options, Result) :- !,
	go(File, legacy, TimeLimit, Options, Result).
run(dump, File, TimeLimit, Options, Result) :-
	atom_concat(File, '.dump', Out),
	guarded(TimeLimit,
		( lps_session:lps_compile(file(File), legacy, Options, Program, Diags),
		  lps_diag:diags_ok(Diags),
		  setup_call_cleanup(open(Out, write, S, [encoding(utf8)]),
				     lps_internal_syntax:dump_internal(Program, S),
				     close(S)) ),
		Result).

go(File, Syntax, TimeLimit, Options, Result) :-
	atom_concat(File, '.lpst', Lpst),
	guarded(TimeLimit,
		( lps_session:lps_run(file(File), Syntax, Options, Run),
		  Run = run(Outcome, Trace, Diags, _),
		  ( lps_diag:diags_ok(Diags) -> true
		  ; forall(member(D, Diags),
			   ( lps_diag:format_diag(D, A), print_message(error, format(A, [])) )),
		    fail ),
		  lps_internal_syntax:write_lpst(Lpst, Trace, Options, Outcome),
		  %  The engine's own verdict, not the harness's: a program that is
		  %  supposed to fail must fail (§0.2), and `failure` here is a
		  %  legitimate outcome recorded as end/-1/failure in the file.
		  Outcome == success ),
		Result).

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
