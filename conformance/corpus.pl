/* corpus.pl — discovering the legacy conformance corpus.

   The corpus is every `.lpst` golden trace under legacy_lps1/examples. Each one is
   named after the *generated* internal-syntax file it tests, e.g.

     goat.pl_.P.lpst   tests   goat.pl_.P   which is generated from   goat.pl

   which is exactly how interpreter:test_examples/1 finds its work: strip `.lpst`,
   regenerate the `_.P` from its source if one exists, then run go/2 on the `_.P`.
*/

:- module(corpus, [
	lps2_root/1,             % -Dir
	legacy_root/1,           % -Dir
	corpus_dir/1,            % -Dir
	corpus_entry/1,          % -entry(Slug, Golden, PFile, Source|none)
	corpus_entry/2,          % +Scope, -Entry
	corpus_entries/1,        % -List           (scope `main`)
	corpus_entries/2,        % +Scopes, -List
	program_features/2       % +PFile, -Features
	]).

:- use_module(library(filesex)).
:- use_module(library(lists)).

:- dynamic lps2_root_cache/1.

%!	lps2_root(-Dir) is det.
lps2_root(Dir) :-
	lps2_root_cache(Dir), !.
lps2_root(Dir) :-
	module_property(corpus, file(F)),
	file_directory_name(F, ConfDir),
	file_directory_name(ConfDir, Dir),
	assertz(lps2_root_cache(Dir)).

legacy_root(Dir) :-
	lps2_root(Root),
	atomic_list_concat([Root, '/legacy_lps1'], Dir).

corpus_dir(Dir) :-
	legacy_root(Legacy),
	atomic_list_concat([Legacy, '/examples'], Dir).

%	corpus_source(?Scope, -GoldenDir, -ProgramDir)
%
%	`main` is examples/, where golden traces sit next to their programs.
%	`extended` is utils/moreTestResults/, six deliberately slow real-time tests that
%	upstream moved out of the way "to avoid lengthy test suite runs" (its README);
%	their programs are still in examples/. They are off by default here for the same
%	reason, but they are part of the corpus and M4 should include them.
corpus_source(main, Dir, Dir) :-
	corpus_dir(Dir).
corpus_source(extended, More, Dir) :-
	corpus_dir(Dir),
	legacy_root(Legacy),
	atomic_list_concat([Legacy, '/utils/moreTestResults'], More).

%!	corpus_entry(-Entry) is nondet.
%!	corpus_entry(+Scope, -Entry) is nondet.
%
%	Entry = entry(Slug, GoldenLpst, PFile, SourceOrNone). Slug is a filesystem-safe
%	identifier derived from the path relative to examples/.

corpus_entry(Entry) :-
	corpus_entry(main, Entry).

corpus_entry(Scope, entry(Slug, Golden, PFile, Source)) :-
	corpus_source(Scope, GoldenDir, ProgramDir),
	find_files(GoldenDir, '.lpst', Golden),
	atom_concat(GoldenDir, Rel0, Golden),
	atom_concat('/', Rel, Rel0),
	atom_concat(RelP, '.lpst', Rel),
	atomic_list_concat([ProgramDir, '/', RelP], PFile),
	exists_file(PFile),
	source_of(PFile, Source),
	slug_of(GoldenDir, Golden, Slug).

corpus_entries(L) :-
	corpus_entries([main], L).

corpus_entries(Scopes, L) :-
	findall(E, ( member(S, Scopes), corpus_entry(S, E) ), L0),
	sort(L0, L).

%!	program_features(+PFile, -Features) is det.
%
%	Cheap textual scan of the internal-syntax program for declarations that make a
%	run depend on the wall clock. `maxRealTime/1` and `minCycleTime/1` bound the run
%	in *real seconds*, so such a program produces a different number of cycles on a
%	different machine — it cannot be part of a deterministic conformance suite as it
%	stands (see docs/dev/semantics/selection-spec.md SP15 and §I.2.3, time is injected).
%	`simulatedRealTimeBeginning/1` on its own is harmless: simulated time advances
%	deterministically per cycle.
program_features(PFile, Features) :-
	catch(read_file_to_string(PFile, S, [encoding(utf8)]), _, S = ""),
	findall(F,
		( member(F-Pat, [ wall_clock-"maxRealTime(",
				  wall_clock-"minCycleTime(",
				  simulated_time-"simulatedRealTimeBeginning(",
				  prolog_events-"prolog_events(",
				  observations-"observe(" ]),
		  sub_string(S, _, _, _, Pat) ),
		F0),
	sort(F0, Features).

%	source_of(+PFile, -Source) — the surface file psyntax would regenerate from,
%	mirroring psyntax:generate_file/1: only `.pl` and `.lps` sources count.
source_of(PFile, Source) :-
	(   atom_concat(Base, '_.P', PFile),
	    (	atom_concat(_, '.pl', Base) -> true
	    ;	atom_concat(_, '.lps', Base)
	    ),
	    exists_file(Base)
	->  Source = Base
	;   Source = none
	).

slug_of(Dir, Golden, Slug) :-
	(   atom_concat(Dir, Rel0, Golden),
	    atom_concat('/', Rel1, Rel0)
	->  true
	;   file_base_name(Golden, Rel1)
	),
	(   atom_concat(Rel2, '_.P.lpst', Rel1)
	->  true
	;   Rel2 = Rel1
	),
	sanitise(Rel2, Slug).

sanitise(A, S) :-
	atom_chars(A, Cs),
	maplist([C,D]>>( char_type(C, alnum) -> D = C
		       ; C == '.' -> D = '.'
		       ; C == '-' -> D = '-'
		       ; D = '_' ), Cs, Ds),
	atom_chars(S, Ds).

%	find_files(+Dir, +Suffix, -File) — recursive, nondet.
find_files(Dir, Suffix, File) :-
	directory_files(Dir, Entries),
	member(E, Entries),
	E \== '.', E \== '..',
	atomic_list_concat([Dir, '/', E], Path),
	(   exists_directory(Path)
	->  find_files(Path, Suffix, File)
	;   atom_concat(_, Suffix, E),
	    File = Path
	).
