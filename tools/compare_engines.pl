/* compare_engines.pl — LPS(1) against LPS2: speed and memory.

   A ballpark, not a benchmark suite. It runs a handful of programs chosen to
   stress different parts of the engine, each in a fresh process, and reports
   wall time, CPU time and peak resident set for both engines.

   What is being compared, precisely: **both engines run the program and write
   a `.lpst`**. LPS2 emits trace records unconditionally (§I.5.2) and cannot
   be asked not to, so comparing it against an untraced legacy run would
   flatter it. Upstream's per-phase wall-clock cutoff is raised from its 0.75 s
   default to 30 s, because at the default it silently discards a phase's work
   and finishes early (selection_spec SP15) — which would look like speed.
   Cycle counts are reported so that any remaining difference in how much work
   each engine actually did is visible rather than hidden in the timings.

   Memory is peak RSS (VmHWM), including the SWI-Prolog runtime, which is why
   the engine-only baseline is measured separately and subtracted in the
   `program` column. Two engines with different internal representations have
   no comparable internal statistic; RSS is the honest one.

   Usage:
     ./myswipl.sh -q -g "consult('tools/compare_engines.pl')" -g "cmp:main" -t halt
     ... -g "cmp:main(['--only', goat])"
*/

:- module(cmp, [ main/0, main/1 ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(process)).
:- use_module(library(filesex)).
:- use_module('../conformance/corpus').

%!	program(?Slug, ?RelativePath, ?Why) is nondet.
%
%	Chosen for coverage of the engine's cost centres, not for size.
program('goat',        'goat.pl_.P',
	'backtracking-heavy: composite events, action commitment, bucket B').
program('philosophers','CLOUT_workshop/diningPhilosophers.pl_.P',
	'concurrent actions, preconditions over action sets').
program('bubbleSort',  'CLOUT_workshop/bubbleSort.pl_.P',
	'timeless/Prolog-heavy, little state').
program('life',        'CLOUT_workshop/life.pl_.P',
	'large state, many intensional fluents per cycle').
program('tictactoe',   'tictactoe.pl_.P',
	'moderate everything').
program('prospGoat2',  'forTesting/prospectiveGoat2.pl_.P',
	'prospective constraints — next-state denials').
program('towers',      'CLOUT_workshop/concurrentTowers.pl_.P',
	'deep composite-event nesting').
program('loanRT',      'CLOUT_workshop/loanAgreementPostConditionsRT.pl_.P',
	'the long one: ~2900 cycles, dates, real-time observations').

main :- main([]).

main(Argv) :-
	( append(_, ['--only', Only|_], Argv) -> true ; Only = '' ),
	( append(_, ['--repeat', RA|_], Argv), atom_number(RA, R) -> true ; R = 2 ),
	baselines(BL, BN),
	format('~nengine load and baseline footprint (no program):~n', []),
	format('  legacy   ~2f s   ~1f MB~n', [BL.time, BL.mb]),
	format('  LPS2   ~2f s   ~1f MB~n', [BN.time, BN.mb]),
	format('~n~w~t~14|~w~t~24|~w~t~34|~w~t~44|~w~t~56|~w~t~68|~w~n',
	       ['program', 'engine', 'cycles', 'wall s', 'cpu s', 'peak MB', 'program MB']),
	%  sub_atom/5 with an empty pattern succeeds once per position, so a bare
	%  filter here enqueues each program once per character of its name.
	findall(S-P-W, ( program(S, P, W), selected(Only, S) ), Ps),
	maplist(compare_one_det(R, BL, BN), Ps, Rows),
	nl,
	summarise(Rows),
	explain(Ps).

selected('', _) :- !.
selected(Only, Slug) :- once(sub_atom(Slug, _, _, _, Only)).

		 /*******************************
		 *	   measurement		*
		 *******************************/

baselines(bl{time: LT, mb: LM}, bl{time: NT, mb: NM}) :-
	measure(legacy_load, 'none', 1, bench(_, _, LT0, _, _, _, LPeak, _, _)),
	measure(lps2_load,   'none', 1, bench(_, _, NT0, _, _, _, NPeak, _, _)),
	LT = LT0, NT = NT0,
	mb(LPeak, LM), mb(NPeak, NM).

%	once/1 per program: a choicepoint left anywhere below would make a later
%	failure re-run an earlier program, and these runs are minutes long.
compare_one_det(Repeat, BL, BN, Prog, Row) :-
	once(compare_one(Repeat, BL, BN, Prog, Row)).

compare_one(Repeat, BL, BN, Slug-Rel-_Why, row(Slug, LegacyR, Lps2R)) :-
	staged(Rel, Slug, legacy, LegacyFile),
	staged(Rel, Slug, lps2,   Lps2File),
	measure(legacy, LegacyFile, Repeat, LegacyB),
	measure(lps2,   Lps2File,   Repeat, Lps2B),
	row_of(LegacyB, BL.mb, LegacyR),
	row_of(Lps2B, BN.mb, Lps2R),
	print_row(Slug, legacy, LegacyR),
	print_row('', 'LPS2', Lps2R),
	flush_output.

row_of(bench(_, _, _, Run, Cpu, _, Peak, Cycles, Outcome), BaseMB,
       r(Cycles, Run, Cpu, PeakMB, ProgMB, Outcome)) :-
	mb(Peak, PeakMB),
	ProgMB is max(0.0, PeakMB - BaseMB).

print_row(Slug, Engine, r(Cycles, Run, Cpu, PeakMB, ProgMB, Outcome)) :-
	( Outcome == success -> Mark = '' ; Mark = Outcome ),
	format('~w~t~14|~w~t~24|~w~t~34|~3f~t~44|~3f~t~56|~1f~t~68|~1f ~w~n',
	       [Slug, Engine, Cycles, Run, Cpu, PeakMB, ProgMB, Mark]).

mb(unknown, 0.0) :- !.
mb(KB, MB) :- MB is KB / 1024.0.

%	Best of N: the first run of anything pays for cold file-system cache,
%	and we are after a floor rather than a distribution.
measure(Engine, File, Repeat, Best) :-
	findall(B, ( between(1, Repeat, _), once(run_child(Engine, File, B)) ), Bs),
	Bs \== [],
	sort(4, @=<, Bs, [Best|_]), !.

run_child(Engine, File, Bench) :-
	lps2_root(Root),
	atomic_list_concat([Root, '/build/bench'], Dir),
	make_directory_path(Dir),
	atomic_list_concat([Dir, '/report.pl'], Report),
	atomic_list_concat([Root, '/tools/bench_child.pl'], Child),
	atomic_list_concat([Root, '/myswipl.sh'], Swipl),
	atomic_list_concat([Dir, '/child.log'], Log),
	ignore(catch(delete_file(Report), _, true)),
	Args = [Child, Engine, Root, File, Report, 400],
	append(['-c', 'exec "$0" "$@" >"$LPS2_LOG" 2>&1', Swipl], Args, ShArgs),
	process_create(path(sh), ShArgs, [process(PID), environment(['LPS2_LOG'=Log])]),
	catch(process_wait(PID, _, [timeout(440)]), _, true),
	(   exists_file(Report),
	    read_term_from_file(Report, Bench)
	->  true
	;   Bench = bench(Engine, File, 0.0, 0.0, 0.0, unknown, unknown, unknown, no_report)
	).

read_term_from_file(File, Term) :-
	setup_call_cleanup(open(File, read, S), read_term(S, Term, []), close(S)),
	Term \== end_of_file.

%	Each engine gets its own copy: running the legacy engine writes a
%	`.lpst` next to the program (hard rule 1), and both engines writing the
%	same path would race.
staged(Rel, Slug, Engine, File) :-
	corpus_dir(Corpus),
	lps2_root(Root),
	atomic_list_concat([Corpus, '/', Rel], Source),
	atomic_list_concat([Root, '/build/bench/', Engine, '/', Slug], Dir),
	make_directory_path(Dir),
	file_base_name(Source, Base),
	atomic_list_concat([Dir, '/', Base], File),
	( exists_file(File) -> true ; copy_file(Source, File) ).

		 /*******************************
		 *	    reporting		*
		 *******************************/

summarise(Rows) :-
	findall(Ratio,
		( member(row(_, r(_, LW, _, _, _, success), r(_, NW, _, _, _, success)), Rows),
		  LW > 0.0, Ratio is NW / LW ),
		Ratios),
	(   Ratios == []
	->  true
	;   sum_list(Ratios, Sum), length(Ratios, N), Mean is Sum / N,
	    min_list(Ratios, Min), max_list(Ratios, Max),
	    format('wall-time ratio LPS2/legacy over ~w comparable runs: ~2f mean, ~2f–~2f~n',
		   [N, Mean, Min, Max])
	),
	findall(MR,
		( member(row(_, r(_, _, _, _, LM, success), r(_, _, _, _, NM, success)), Rows),
		  LM > 0.1, MR is NM / LM ),
		MRs),
	(   MRs == []
	->  true
	;   sum_list(MRs, S2), length(MRs, N2), M2 is S2 / N2,
	    min_list(MRs, Mn2), max_list(MRs, Mx2),
	    format('program-memory ratio LPS2/legacy: ~2f mean, ~2f–~2f~n', [M2, Mn2, Mx2])
	).

explain(Ps) :-
	format('~nwhat each program stresses:~n', []),
	forall(member(S-_-W, Ps), format('  ~w~t~14| ~w~n', [S, W])).
