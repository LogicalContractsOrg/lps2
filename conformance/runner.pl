/* runner.pl — the M0 conformance harness (§I.1.1, §I.1.2).

   Two jobs:

   1. Run every `.lpst` in the corpus through an engine adapter and compare with
      upstream semantics (lpst.pl). Today there is one adapter, the legacy engine;
      the new engine gets a second one at M1 without changing anything here.

   2. Classify each test into buckets A/B/C by re-running it under perturbations
      that a declarative reading of LPS says should not matter (perturb.pl):

        A  invariant under every perturbation           — real correctness
        B  changes under a program/engine perturbation  — conformance needs a
                                                          stated selection rule
        C  changes under a byte-identical rerun         — depends on the clock,
                                                          machine speed or hashing

   Usage:
     ./myswipl.sh -g "consult('conformance/runner.pl')" -g main -t halt -- [ARGS]
       --only Substring     run just the entries whose slug contains Substring
       --variants a,b,c     run just these perturbations (default: all)
       --jobs N             N concurrent entries (default 1; >1 risks polluting the
                            C bucket, since the legacy engine time-limits its phases)
       --limit N            only the first N entries
       --no-report          skip writing docs/dev/conformance/conformance_report.md
       --upstream           also let the legacy engine check itself against each
                            golden trace with its own run_test machinery, and
                            report any disagreement with our comparison
*/

:- module(runner, [ main/0, main/1, run_corpus/2, report/1 ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(thread)).
:- use_module(library(filesex)).
:- use_module(corpus).
:- use_module(lpst).
:- use_module(perturb).
:- use_module(adapter_legacy).
:- use_module(adapter_lps2).
:- use_module(regenerated).
:- use_module(adjudicated).

:- dynamic result/6.      % Slug, Variant, Status, Seconds, Verdict, Failures
:- dynamic bucket/3.      % Slug, Bucket, SensitiveTo
:- dynamic upstream/4.    % Slug, OurVerdict, UpstreamVerdict, agree|disagree
:- dynamic features/2.    % Slug, program features (see corpus:program_features/2)

main :-
	current_prolog_flag(argv, Argv),
	main(Argv).

main(Argv) :-
	parse_args(Argv, Opts),
	(   memberchk(report_only, Opts)
	->  load_results(Opts, Entries)
	;   run_corpus(Opts, Entries)
	),
	classify,
	(   memberchk(upstream, Opts)
	->  upstream_check(Entries)
	;   true
	),
	summarise(Entries, Opts),
	(   memberchk(no_report, Opts)
	->  true
	;   report(Entries, Opts)
	).

parse_args([], []).
parse_args(['--only', S|T], [only(S)|O]) :- !, parse_args(T, O).
parse_args(['--variants', S|T], [variants(Vs)|O]) :- !,
	atomic_list_concat(Vs, ',', S), parse_args(T, O).
parse_args(['--jobs', S|T], [jobs(N)|O]) :- !, atom_number(S, N), parse_args(T, O).
parse_args(['--limit', S|T], [limit(N)|O]) :- !, atom_number(S, N), parse_args(T, O).
parse_args(['--no-report'|T], [no_report|O]) :- !, parse_args(T, O).
parse_args(['--upstream'|T], [upstream|O]) :- !, parse_args(T, O).
parse_args(['--extended'|T], [extended|O]) :- !, parse_args(T, O).
parse_args(['--time-limit', S|T], [time_limit(N)|O]) :- !, atom_number(S, N), parse_args(T, O).
parse_args(['--report-only'|T], [report_only|O]) :- !, parse_args(T, O).
parse_args(['--engine', S|T], [engine(E)|O]) :- !, atom_string(E, S), parse_args(T, O).
parse_args(['--report', S|T], [report_file(S)|O]) :- !, parse_args(T, O).
parse_args(['--results', S|T], [results_file(S)|O]) :- !, parse_args(T, O).
parse_args([_|T], O) :- parse_args(T, O).

variants(Opts, Vs) :-
	(   memberchk(variants(Vs0), Opts)
	->  Vs = Vs0
	;   findall(V, perturbation(V, _, _), Vs)
	).

%!	run_corpus(+Opts, -Entries) is det.
run_corpus(Opts, Entries) :-
	retractall(result(_,_,_,_,_,_)),
	retractall(bucket(_,_,_)),
	(   memberchk(time_limit(TL), Opts) -> set_time_limit(TL) ; true ),
	(   memberchk(extended, Opts) -> Scopes = [main, extended] ; Scopes = [main] ),
	corpus_entries(Scopes, All),
	include(selected(Opts), All, Sel0),
	(   memberchk(limit(N), Opts)
	->  length(Sel0, L), Take is min(N, L), length(Entries, Take), append(Entries, _, Sel0)
	;   Entries = Sel0
	),
	variants(Opts, Vs),
	engine_of(Opts, Engine),
	forall(member(V, Vs), build_engine_variant(V)),
	length(Entries, NE),
	format('engine ~w: ~w entries x ~w variants~n', [Engine, NE, Vs]),
	(   memberchk(jobs(J), Opts), J > 1
	->  concurrent_maplist(run_entry(Engine, Vs), Entries, Results)
	;   maplist(run_entry(Engine, Vs), Entries, Results)
	),
	forall(( member(RL, Results), member(R, RL) ), assertz(R)),
	retractall(features(_,_)),
	forall(member(entry(Slug,_,PFile,_), Entries),
	       ( program_features(PFile, Fs), assertz(features(Slug, Fs)) )).

%!	load_results(+Opts, -Entries) is det.
%
%	Re-emit the report from build/results.pl without re-running the corpus.
load_results(Opts, Entries) :-
	retractall(result(_,_,_,_,_,_)),
	retractall(bucket(_,_,_)),
	retractall(features(_,_)),
	lps2_root(Root),
	(   memberchk(results_file(RF), Opts)
	->  atomic_list_concat([Root, '/', RF], DataFile)
	;   atomic_list_concat([Root, '/build/results.pl'], DataFile)
	),
	setup_call_cleanup(
	    open(DataFile, read, S, [encoding(utf8)]),
	    load_result_terms(S),
	    close(S)),
	(   memberchk(extended, Opts) -> Scopes = [main, extended] ; Scopes = [main] ),
	corpus_entries(Scopes, All),
	include([entry(Slug,_,_,_)]>>result(Slug,_,_,_,_,_), All, Entries),
	forall(member(entry(Slug,_,PFile,_), Entries),
	       ( program_features(PFile, Fs), assertz(features(Slug, Fs)) )).

load_result_terms(S) :-
	read_term(S, T, []),
	(   T == end_of_file
	->  true
	;   (   T = result(_,_,_,_,_,_) -> assertz(T) ; true ),
	    load_result_terms(S)
	).

selected(Opts, entry(Slug,_,_,_)) :-
	(   memberchk(only(S), Opts)
	->  sub_atom(Slug, _, _, _, S)
	;   true
	).

%!	engine_of(+Opts, -Engine) is det.
%
%	`legacy` is the LPS(1) interpreter (the reference); `lps2` is the new
%	engine. §I.1.1's point is that the harness is independent of both, so
%	this is the only place that knows the difference.
engine_of(Opts, Engine) :-
	(   memberchk(engine(E), Opts) -> Engine = E ; Engine = legacy ).

%	One entry, all variants, sequentially (variants share the staged program).
run_entry(Engine, Vs0, Entry, Results) :-
	Entry = entry(Slug, _, _, _),
	catch(run_entry_(Engine, Vs0, Entry, Results, Summary), E,
	      ( Results = [result(Slug, none, error(E), 0, verdict(fail,fail,[]), [harness_error(E)])],
		Summary = harness_error )),
	format('~w~t~60| ~w~n', [Slug, Summary]),
	report_baseline_failure(Results),
	flush_output.

%	A one-line summary is enough when a test passes; when it does not, the
%	first couple of diagnoses are what you actually need, and re-running a
%	35-minute suite to get them is not a workflow.
report_baseline_failure(Results) :-
	(   memberchk(result(_, none, _, _, verdict(_, fail, Failures), _), Results),
	    Failures \== []
	->  first_n(2, Failures, Shown),
	    forall(member(F, Shown),
		   ( format(atom(A), '~q', [F]),
		     sub_atom_upto(A, 200, A1),
		     format('    ~w~n', [A1]) ))
	;   true
	).

run_entry_(Engine, Vs0, Entry, Results, Summary) :-
	Entry = entry(Slug, Golden0, _, _),
	golden_for(Engine, Slug, Golden0, Golden),
	lpst_read(Golden, GoldenTrace),
	lpst_options(GoldenTrace, Opts0),
	(   memberchk(dc, Opts0) -> Options = Opts0 ; append(Opts0, [dc], Options) ),
	(   memberchk(none, Vs0) -> Vs = Vs0 ; Vs = [none|Vs0] ),
	maplist(run_variant(Engine, Entry, GoldenTrace, Options), Vs, Results),
	(   memberchk(result(_, none, St, _, verdict(U,_,_), _), Results)
	->  findall(V, ( member(result(_,V,_,_,verdict(fail,_,_),_), Results), V \== none ), Sens),
	    Summary = base(U, St)-sensitive(Sens)
	;   Summary = no_baseline
	).

run_variant(cross, Entry, _GoldenTrace, Options, Variant,
	    result(Slug, Variant, Status, Seconds, Verdict, Failures)) :- !,
	%  Engine against engine, not engine against golden. This is the only
	%  meaningful comparison when a golden is older than upstream's own
	%  behaviour — six of the extended entries were recorded in 2019, before
	%  the engine began recording real_date_begin/real_date_end as
	%  composites, and today's legacy engine fails them exactly as LPS2
	%  does. Asking whether the two engines agree *with each other* answers
	%  the question the corpus was supposed to answer.
	Entry = entry(Slug, _, _, _),
	engine_run(legacy, Entry, Variant, Options, run(LStatus, LTrace, LSecs)),
	engine_run(lps2, Entry, Variant, Options, run(Status, Trace, Secs)),
	Seconds is LSecs + Secs,
	(   ( Trace == none ; LTrace == none )
	->  Verdict = verdict(fail, fail, []),
	    Failures = [no_trace(lps2(Status), legacy(LStatus))]
	;   lpst_compare(Trace, LTrace, Verdict),
	    Verdict = verdict(_, _, Failures)
	).
run_variant(Engine, Entry, GoldenTrace, Options, Variant,
	    result(Slug, Variant, Status, Seconds, Verdict, Failures)) :-
	Entry = entry(Slug, _, _, _),
	engine_run(Engine, Entry, Variant, Options, run(Status, Trace, Seconds)),
	(   Trace == none
	->  Verdict = verdict(fail, fail, []),
	    Failures = [no_trace(Status)]
	;   lpst_compare(Trace, GoldenTrace, Verdict),
	    Verdict = verdict(_, _, Failures)
	).

%!	golden_for(+Engine, +Slug, +Default, -Golden) is det.
%
%	LPS2 is compared against a regenerated golden where one exists
%	(conformance/regenerated.pl says which and why). The legacy engine is
%	always compared against its own 2021 trace — those entries are exactly
%	the ones it cannot reproduce deterministically, and pretending otherwise
%	would hide that.
golden_for(lps2, Slug, _Default, Golden) :-
	regenerated_golden(Slug, Golden, _), !.
golden_for(_, _, Default, Default).

engine_run(legacy, Entry, Variant, Options, Result) :- !,
	legacy_run(Entry, Variant, Options, Result).
engine_run(lps2, Entry, Variant, Options, Result) :-
	lps2_run(Entry, Variant, Options, Result).

%!	classify is det.
classify :-
	retractall(bucket(_,_,_)),
	forall(distinct_slug(Slug), classify(Slug)).

distinct_slug(Slug) :-
	findall(S, result(S,_,_,_,_,_), L), sort(L, Slugs), member(Slug, Slugs).

%	Classification uses the *strict* verdict, not upstream's. Upstream drives its
%	comparison from the cycles the run actually produced, so a run that dies early
%	is scored "ok" as long as nothing it did produce contradicted the golden —
%	`CLOUT_workshop/life.pl` does exactly this, finishing anywhere between 0 and 10
%	of its 10 cycles depending on machine load (selection_spec.md SP15). For LPS2
%	a truncated trace is not a pass.
classify(Slug) :-
	(   result(Slug, none, _, _, verdict(_,fail,_), _),
	    adjudicated(Slug, Class, _)
	->  assertz(bucket(Slug, adjudicated(Class), []))
	;   classify_(Slug)
	).

classify_(Slug) :-
	(   result(Slug, none, _, _, verdict(_,pass,_), _)
	->  findall(V, ( result(Slug, V, _, _, verdict(_,fail,_), _), V \== none ), Sensitive),
	    (	Sensitive == []
	    ->	B = a
	    ;	memberchk(rerun, Sensitive)
	    ->	B = c                    % unstable even against itself: clock/speed/hash
	    ;	memberchk(rewrite, Sensitive)
	    ->	B = rewrite_artifact     % our read/write round-trip changed the program
	    ;	B = b
	    ),
	    assertz(bucket(Slug, B, Sensitive))
	;   result(Slug, none, Status, _, _, _)
	->  findall(V, ( result(Slug, V, _, _, verdict(_,pass,_), _), V \== none ), Ok),
	    (	Ok == []
	    ->	assertz(bucket(Slug, baseline_fail, [Status]))
	    ;	% the baseline failed but some perturbation of it passed: the test is not
		% systematically broken, it is unstable
		assertz(bucket(Slug, c, [baseline(Status), passing(Ok)]))
	    )
	;   assertz(bucket(Slug, not_run, []))
	).

%!	upstream_check(+Entries) is det.
%
%	Validate the harness itself: our verdict must agree with the legacy engine's
%	own run_test verdict on every entry.
upstream_check(Entries) :-
	retractall(upstream(_,_,_,_)),
	forall(member(E, Entries), upstream_check_one(E)),
	findall(S, upstream(S,_,_,disagree), D),
	length(D, ND),
	(   ND =:= 0
	->  format('~nupstream cross-check: full agreement~n', [])
	;   format('~nupstream cross-check: ~w DISAGREEMENTS: ~w~n', [ND, D])
	).

upstream_check_one(E) :-
	E = entry(Slug, Golden, _, _),
	lpst_read(Golden, GT),
	lpst_options(GT, O0),
	(   memberchk(dc, O0) -> O = O0 ; append(O0, [dc], O) ),
	legacy_verify(E, O, V),
	(   result(Slug, none, _, _, verdict(U,_,_), _) -> true ; U = unknown ),
	(   ( U == pass, V == pass ; U == fail, V = fail(_,_) )
	->  A = agree
	;   A = disagree
	),
	assertz(upstream(Slug, U, V, A)),
	(   A == disagree
	->  format('  DISAGREE ~w: ours=~w upstream=~w~n', [Slug, U, V])
	;   true
	).

summarise(Entries, _Opts) :-
	length(Entries, N),
	findall(B-S, bucket(S,B,_), Pairs),
	msort(Pairs, Sorted),
	format('~n=== M0 corpus classification (~w entries) ===~n', [N]),
	bucket_names(Names),
	forall(member(B, Names),
	       ( findall(S, member(B-S, Sorted), L), length(L, K),
		 (   N > 0 -> Pct is 100*K/N ; Pct = 0 ),
		 format('  bucket ~w~t~34| ~w~t~40| (~1f%)~n', [B, K, Pct]) )).

%	The fixed buckets plus one per adjudication class actually in use, so a
%	new class added to conformance/adjudicated.pl shows up in the summary
%	instead of silently landing in `baseline_fail`.
bucket_names(Names) :-
	findall(adjudicated(C), ( adjudicated(_, C, _) ), Cs0),
	sort(Cs0, Cs),
	append([a, b, c, rewrite_artifact], Cs, N0),
	append(N0, [baseline_fail, not_run], Names).

report(Entries) :- report(Entries, []).

%!	report(+Entries, +Opts) is det.
%
%	The M0 report (the legacy engine's) and the M4 report (LPS2's) are
%	different documents; writing both to the same path would mean the last
%	run to finish decides what the repository says.
report(Entries, Opts) :-
	lps2_root(Root),
	(   memberchk(results_file(RF), Opts)
	->  atomic_list_concat([Root, '/', RF], DataFile)
	;   atomic_list_concat([Root, '/build/results.pl'], DataFile)
	),
	(   memberchk(report_file(MF), Opts)
	->  atomic_list_concat([Root, '/', MF], MdFile)
	;   atomic_list_concat([Root, '/docs/dev/conformance/conformance_report.md'], MdFile)
	),
	make_directory_path_of(DataFile),
	engine_of(Opts, Engine),
	write_data(DataFile),
	write_markdown(MdFile, Entries, Engine),
	format('~nwrote ~w~n     ~w~n', [DataFile, MdFile]).

make_directory_path_of(File) :-
	file_directory_name(File, Dir),
	make_directory_path(Dir).

write_data(File) :-
	setup_call_cleanup(
	    open(File, write, S, [encoding(utf8)]),
	    ( format(S, '% generated by conformance/runner.pl~n', []),
	      forall(result(A,B,C,D,E,F),
		     \+ \+ ( numbervars(f(A,B,C,D,E,F), 0, _),
			     write_term(S, result(A,B,C,D,E,F),
					[quoted(true), numbervars(true)]),
			     write(S, '.'), nl(S) )),
	      forall(bucket(A,B,C),
		     \+ \+ ( numbervars(f(A,B,C), 0, _),
			     write_term(S, bucket(A,B,C), [quoted(true), numbervars(true)]),
			     write(S, '.'), nl(S) )) ),
	    close(S)).

write_markdown(File, Entries, Engine) :-
	length(Entries, N),
	findall(V, perturbation(V,_,_), Vs),
	setup_call_cleanup(
	    open(File, write, S, [encoding(utf8)]),
	    write_markdown_(S, N, Vs, Engine),
	    close(S)).

write_markdown_(S, N, Vs, Engine) :-
	engine_title(Engine, Title, Blurb),
	format(S, '# ~w~n~n', [Title]),
	format(S, 'Generated by `conformance/runner.pl`. Do not hand-edit; see~n', []),
	format(S, '`docs/dev/semantics/selection-spec.md` for the analysis this feeds.~n~n', []),
	format(S, 'Corpus: ~w `.lpst` golden traces under `legacy_lps1/examples`,~n', [N]),
	format(S, '~w~n~n', [Blurb]),
	write_adjudications(S),
	format(S, '## Buckets~n~n', []),
	format(S, '| bucket | meaning | count | % |~n|---|---|---:|---:|~n', []),
	bucket_names(Names),
	forall(( member(B, Names), bucket_meaning(B, Meaning) ),
	       ( findall(X, bucket(X,B,_), L), length(L, K),
		 ( N > 0 -> Pct is 100*K/N ; Pct = 0 ),
		 format(S, '| ~w | ~w | ~w | ~1f |~n', [B, Meaning, K, Pct]) )),
	nl(S),
	format(S, '## Perturbations~n~n', []),
	format(S, '| name | kind | description | tests it changes |~n|---|---|---|---:|~n', []),
	forall(member(V, Vs),
	       ( perturbation(V, Kind, Desc),
		 findall(X, result(X, V, _, _, verdict(fail,_,_), _), L), length(L, K),
		 format(S, '| `~w` | ~w | ~w | ~w |~n', [V, Kind, Desc, K]) )),
	nl(S),
	findall(X-V, ( result(X, V, _, _, verdict(pass, fail, _), _) ), Loose0),
	sort(Loose0, Loose1),
	findall(X, member(X-_, Loose1), Loose2), sort(Loose2, Loose),
	length(Loose, NL),
	format(S, '## Where upstream semantics are weaker than they look~n~n', []),
	format(S, 'Upstream drives the comparison from the stages/cycles the *actual* run~n', []),
	format(S, 'produced, so a golden entry the run never reaches is never noticed: a run~n', []),
	format(S, 'that dies half way scores "ok". This harness therefore classifies on its~n', []),
	format(S, 'own *strict* verdict, which also requires the golden cycles to be covered,~n', []),
	format(S, 'and reports upstream''s verdict alongside. Tests where some run passed~n', []),
	format(S, 'upstream but left golden cycles uncovered: **~w**~n~n', [NL]),
	(   Loose == []
	->  true
	;   forall(member(X, Loose), format(S, '- `~w`~n', [X])), nl(S)
	),
	findall(X, ( features(X, F), memberchk(wall_clock, F) ), Wall),
	length(Wall, NW),
	findall(X, bucket(X, baseline_fail, _), Fails),
	format(S, '## Baseline failures~n~n', []),
	format(S, 'Tests where the *legacy engine itself*, on this machine and this~n', []),
	format(S, 'SWI-Prolog, no longer reproduces its own 2021 golden trace. These need~n', []),
	format(S, 'adjudication before they can mean anything for LPS2.~n~n', []),
	(   Fails == []
	->  format(S, 'None.~n~n', [])
	;   forall(member(X, Fails), write_failure(S, X)), nl(S)
	),
	format(S, '## Wall-clock-bound programs~n~n', []),
	format(S, 'Programs declaring `maxRealTime/1` or `minCycleTime/1` run for a number of~n', []),
	format(S, 'cycles that depends on machine speed, so their golden traces are not~n', []),
	format(S, 'reproducible by construction on different hardware: **~w** of ~w.~n~n', [NW, N]),
	(   Wall == []
	->  true
	;   forall(member(X, Wall),
		   ( ( bucket(X, B1, _) -> true ; B1 = '-' ),
		     format(S, '- `~w` (bucket ~w)~n', [X, B1]) )), nl(S)
	),
	format(S, '## Per-test detail~n~n', []),
	format(S, '| test | bucket | sensitive to | baseline status | features |~n|---|---|---|---|---|~n', []),
	forall(bucket(Slug, B, Sens),
	       ( ( result(Slug, none, St, _, _, _) -> true ; St = '-' ),
		 ( features(Slug, F1) -> true ; F1 = [] ),
		 format(S, '| `~w` | ~w | ~w | ~w | ~w |~n', [Slug, B, Sens, St, F1]) )).

engine_title(lps2, 'M4 — LPS2 against the corpus',
	     'each run through LPS2 with the golden file\'s own recorded options plus `dc`.').
engine_title(cross, 'LPS2 against the legacy engine, trace for trace',
	     'each entry run through *both* engines, comparing their traces with each\c
	      other rather than with the golden — the comparison that means something\c
	      when a golden predates upstream\'s own behaviour.').
engine_title(_, 'M0 — conformance harness and corpus classification',
	     'each run against the legacy engine with its own recorded options plus `dc`.').

%	§I.1.5: every entry that cannot meet its golden carries a written,
%	reviewed justification. This is that register, rendered.
write_adjudications(S) :-
	findall(Slug-Class-Why, adjudicated(Slug, Class, Why), As),
	(   As == []
	->  true
	;   format(S, '## Adjudicated entries~n~n', []),
	    format(S, 'Entries whose golden trace cannot be met, with the reason (§I.1.5).~n', []),
	    format(S, 'These are *not* passes; they are failures traced to the corpus~n', []),
	    format(S, 'rather than to the engine, and each names its evidence.~n~n', []),
	    forall(member(Slug-Class-Why, As),
		   format(S, '- `~w` — **~w**. ~w~n', [Slug, Class, Why])),
	    nl(S)
	).

bucket_meaning(a, 'invariant under every perturbation').
bucket_meaning(b, 'choice-sensitive; needs a stated selection rule').
bucket_meaning(c, 'diverges on an identical rerun (clock/speed/hash)').
bucket_meaning(rewrite_artifact, 'changes when the program is merely re-serialised — a harness artifact').
bucket_meaning(baseline_fail, 'does not reproduce its golden trace here, and is not adjudicated').
bucket_meaning(not_run, 'not run').
bucket_meaning(adjudicated(C), M) :-
	format(atom(M), 'adjudicated: ~w — see conformance/adjudicated.pl', [C]).

%	One baseline failure, with the first few diagnoses only: a diverging long run
%	can produce thousands of `missing_cycle/2` terms.
write_failure(S, Slug) :-
	( result(Slug, none, St, Secs, _, Fs) -> true ; St = '-', Secs = 0, Fs = [] ),
	length(Fs, NF),
	first_n(3, Fs, Shown),
	format(S, '- `~w` — status `~w` after ~1fs, ~w diagnoses:~n', [Slug, St, Secs, NF]),
	forall(member(F, Shown),
	       ( format(atom(A), '~q', [F]),
		 sub_atom_upto(A, 150, A1),
		 format(S, '  - `~w`~n', [A1]) )).

first_n(0, _, []) :- !.
first_n(_, [], []) :- !.
first_n(N, [X|Xs], [X|Ys]) :- N1 is N-1, first_n(N1, Xs, Ys).

sub_atom_upto(A, Max, Out) :-
	atom_length(A, L),
	(   L =< Max
	->  Out = A
	;   sub_atom(A, 0, Max, _, P), atom_concat(P, ' …', Out)
	).
