/* bench_child.pl — one engine, one program, one process, measured.

   Run in its own process so that peak RSS means something: a shared process
   would report the high-water mark of whichever engine ran first, and Prolog
   never gives memory back to the OS.

     swipl tools/bench_child.pl ENGINE ROOT FILE REPORT TIMELIMIT

   ENGINE is legacy | lps2 | legacy_load | lps2_load. The two `_load` variants
   load the engine and stop, which is how the load cost and the runtime's own
   footprint are separated from the program's.

   Both engines are asked to do the *same work*: run the program and write a
   `.lpst`. That matters, because LPS2 emits trace records unconditionally
   (§I.5.2) while upstream only does so under `make_test` — comparing a traced
   run with an untraced one would flatter us.

   Upstream's per-phase wall-clock limit is raised to 30 s (`timeout(30)`).
   Left at its 0.75 s default it silently discards a phase's work and finishes
   early (selection_spec SP15), which would show up here as the old engine
   being fast when it was really being incomplete. Cycle counts are reported so
   any remaining truncation is visible.

   Writes one term:
     bench(Engine, File, LoadSeconds, RunSeconds, CpuSeconds,
	   RssAfterLoadKB, PeakRssKB, Cycles, Outcome)
*/

:- initialization(main, main).

main(Argv) :-
	Argv = [EngineA, Root, File, Report, TimeLimitA],
	atom_number(TimeLimitA, TimeLimit),
	atom_string(Engine, EngineA),
	get_time(L0),
	load_engine(Engine, Root),
	get_time(L1),
	Load is L1 - L0,
	peak_rss(AfterLoad),
	(   run_mode(Engine)
	->  get_time(R0),
	    statistics(cputime, C0),
	    run(Engine, File, TimeLimit, Cycles, Outcome),
	    statistics(cputime, C1),
	    get_time(R1),
	    Run is R1 - R0, Cpu is C1 - C0
	;   Run = 0.0, Cpu = 0.0, Cycles = 0, Outcome = load_only
	),
	peak_rss(Peak),
	save(Report, bench(Engine, File, Load, Run, Cpu, AfterLoad, Peak, Cycles, Outcome)).

run_mode(legacy).
run_mode(lps2).

load_engine(E, Root) :-
	( E == legacy ; E == legacy_load ), !,
	atomic_list_concat([Root, '/legacy_lps1/utils/psyntax.P'], Psyntax),
	catch(consult(Psyntax), Ex, ( print_message(error, Ex), halt(4) )).
load_engine(_, Root) :-
	atomic_list_concat([Root, '/src/lps.pl'], Loader),
	catch(consult(Loader), Ex, ( print_message(error, Ex), halt(4) )).

run(legacy, File, TimeLimit, Cycles, Outcome) :- !,
	guarded(TimeLimit,
		interpreter:go(File, [dc, make_test, silent, timeout(30)]),
		Outcome),
	(   catch(db:current_time(T), _, fail)
	->  Cycles is T - 1
	;   Cycles = unknown
	).
run(lps2, File, TimeLimit, Cycles, Outcome) :-
	atom_concat(File, '.lpst', Lpst),
	guarded(TimeLimit,
		( lps_session:lps_run(file(File), internal, [dc], Run),
		  Run = run(O, Trace, _, S),
		  lps_internal_syntax:write_lpst(Lpst, Trace, [dc], O),
		  ( S == none -> true ; lps_session:lps_session_time(S, T), nb_setval(cycles, T) ) ),
		Outcome),
	(   catch(nb_getval(cycles, T2), _, fail)
	->  Cycles is T2 - 1
	;   Cycles = unknown
	).

guarded(TimeLimit, Goal, Result) :-
	catch(call_with_time_limit(TimeLimit,
		  ( catch(Goal, In, true)
		  -> ( var(In) -> Result = success ; Result = error(In) )
		  ;  Result = failed )),
	      Out,
	      ( Out == time_limit_exceeded -> Result = timeout ; Result = error(Out) )).

%!	peak_rss(-KB) is det.
%
%	VmHWM from /proc — the high-water mark of resident set size, which is
%	the only memory number that is comparable across two engines with very
%	different internal representations. Linux-specific, and this is a
%	measurement tool, not the engine.
peak_rss(KB) :-
	(   catch(read_vmhwm('/proc/self/status', KB), _, fail)
	->  true
	;   KB = unknown
	).

read_vmhwm(File, KB) :-
	setup_call_cleanup(open(File, read, S), scan_vmhwm(S, KB), close(S)).

scan_vmhwm(S, KB) :-
	read_line_to_string(S, Line),
	Line \== end_of_file,
	(   sub_string(Line, 0, _, _, "VmHWM:")
	->  split_string(Line, " \t", " \t", Parts),
	    member(P, Parts), number_string(KB, P), !
	;   scan_vmhwm(S, KB)
	).

save(File, Term) :-
	setup_call_cleanup(open(File, write, S),
			   ( \+ \+ ( numbervars(Term, 0, _),
				     write_term(S, Term, [quoted(true), numbervars(true)]),
				     write(S, '.'), nl(S) ) ),
			   close(S)).
