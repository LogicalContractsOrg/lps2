/* adapter_legacy.pl — engine adapter for the legacy LPS(1) interpreter.

   The harness never touches legacy_lps1/: running the legacy engine writes next to
   the program it runs (regenerated `_.P`, and the `.lpst` under make_test). So every
   run happens in build/work/<slug>/<variant>/ on copies.

   Staging (once per corpus entry):
     copy the `_.P` and, if it exists, its `.pl`/`.lps` source into .../base/,
     then ask psyntax to regenerate the `_.P` — this is what
     interpreter:test_examples/1 does before running the suite. The source is then
     dropped from the work dir so later runs use the generated `_.P` verbatim and
     perturbations of it survive.

   Running:
     interpreter:go(P, [make_test|Options]) in a fresh process, where Options are the
     golden file's own `lps_test_options/1` plus `dc` — mirroring
     interpreter:test_examples_dc/0, which runs the suite as [run_test, dc] on top of
     the recorded options. The engine writes P.lpst; that file *is* the actual trace.
*/

:- module(adapter_legacy, [
	legacy_stage/2,          % +Entry, -StagedPFile
	legacy_run/4,            % +Entry, +Variant, +Options, -Result
	legacy_verify/3,         % +Entry, +Options, -pass|fail(Status,Terms)
	set_time_limit/1,        % +Seconds
	time_limit/1,            % -Seconds
	engine_dir/2,            % +Variant, -EngineDir
	build_engine_variant/1,  % +Variant
	work_dir/3               % +Slug, +Variant, -Dir
	]).

:- use_module(library(filesex)).
:- use_module(library(process)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(corpus).
:- use_module(lpst).
:- use_module(perturb).

:- dynamic time_limit_setting/1.

%!	time_limit(-Seconds) is det.
%
%	Per-run limit inside the child. Everything in the corpus finishes in under a
%	second except the real-time contract examples, which are wall-clock bound by
%	construction (`maxRealTime`, `minCycleTime`): `loanAgreementPostConditionsRT`
%	needs ~115 s here, so the default must be comfortably above that or the test
%	shows up as a spurious baseline failure.
time_limit(S) :-
	(   time_limit_setting(S0) -> S = S0 ; S = 300 ).

set_time_limit(S) :-
	retractall(time_limit_setting(_)),
	assertz(time_limit_setting(S)).

%!	work_dir(+Slug, +Variant, -Dir) is det.
work_dir(Slug, Variant, Dir) :-
	lps2_root(Root),
	atomic_list_concat([Root, '/build/work/', Slug, '/', Variant], Dir).

%!	legacy_stage(+Entry, -StagedP) is semidet.
legacy_stage(entry(Slug, _Golden, PFile, Source), StagedP) :-
	work_dir(Slug, base, Dir),
	make_directory_path(Dir),
	file_base_name(PFile, PBase),
	atomic_list_concat([Dir, '/', PBase], StagedP),
	(   exists_file(StagedP)
	->  true                              % already staged
	;   copy_file(PFile, StagedP),
	    (	Source == none
	    ->	true
	    ;	file_base_name(Source, SBase),
		atomic_list_concat([Dir, '/', SBase], StagedSource),
		copy_file(Source, StagedSource),
		run_child(legacy, generate, StagedP, [], 60, Dir, _Status),
		delete_file(StagedSource)
	    )
	).

%!	engine_dir(+Variant, -Dir) is det.
%
%	The unperturbed engine is legacy_lps1 itself; engine perturbations get a
%	patched copy under build/engine/<Variant>/.
engine_dir(Variant, Dir) :-
	perturbation(Variant, engine, _), !,
	lps2_root(Root),
	atomic_list_concat([Root, '/build/engine/', Variant], Dir).
engine_dir(_, Dir) :-
	legacy_root(Dir).

%!	build_engine_variant(+Variant) is det.
build_engine_variant(Variant) :-
	\+ perturbation(Variant, engine, _), !.
build_engine_variant(Variant) :-
	engine_dir(Variant, Dir),
	exists_directory(Dir), !.
build_engine_variant(Variant) :-
	engine_dir(Variant, Dir),
	legacy_root(Legacy),
	make_directory_path(Dir),
	forall(member(Sub, [engine, utils]),
	       ( atomic_list_concat([Legacy, '/', Sub], From),
		 atomic_list_concat([Dir, '/', Sub], To),
		 copy_directory(From, To) )),
	patch_engine(Variant, Dir).

patch_engine(queue_prepend, Dir) :-
	atomic_list_concat([Dir, '/engine/interpreter.P'], F),
	patch_file(F,
		   'append(Gi, NewGi, NGi), % Puts new goals at the end of the queue.',
		   'append(NewGi, Gi, NGi), % PERTURBED: new goals at the front of the queue.').

patch_file(File, From, To) :-
	read_file_to_string(File, S0, [encoding(utf8)]),
	(   replace_substring(S0, From, To, S)
	->  true
	;   throw(error(patch_target_not_found(File, From), _))
	),
	setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
			   write(Out, S),
			   close(Out)).

replace_substring(S0, From, To, S) :-
	sub_string(S0, B, _, A, From),
	sub_string(S0, 0, B, _, Pre),
	sub_string(S0, _, A, 0, Post),
	atomics_to_string([Pre, To, Post], S).

%!	legacy_run(+Entry, +Variant, +Options, -Result) is det.
%
%	Result = run(Status, Trace, Seconds) with Status one of
%	success/failed/error(E)/timeout/no_trace, and Trace an lpst/5 term or `none`.

legacy_run(Entry, Variant, Options, run(Status, Trace, Seconds)) :-
	Entry = entry(Slug, _Golden, _P, _Src),
	legacy_stage(Entry, StagedP),
	work_dir(Slug, Variant, Dir),
	prepare_dir(Dir),
	file_base_name(StagedP, PBase),
	atomic_list_concat([Dir, '/', PBase], RunP),
	perturb_program(Variant, StagedP, RunP),
	engine_dir(Variant, EngineDir),
	get_time(T0),
	time_limit(TL),
	run_child(EngineDir, run, RunP, Options, TL, Dir, Status0),
	get_time(T1),
	Seconds is T1 - T0,
	atom_concat(RunP, '.lpst', ActualFile),
	(   exists_file(ActualFile)
	->  catch(lpst_read(ActualFile, Trace), _, Trace = none)
	;   Trace = none
	),
	(   Trace == none, Status0 == success
	->  Status = no_trace
	;   Status = Status0
	).

%!	legacy_verify(+Entry, +Options, -Verdict) is det.
%
%	Cross-validation of our own comparison: let the *legacy* engine check itself
%	against the golden trace with its own `run_test` machinery. Upstream's
%	criterion (interpreter:do_test_suite/3) is "go/2 succeeded and nothing was
%	recorded in lps_failed_test/2". Any disagreement with lpst_compare/3 is a bug
%	in the harness and must be investigated before the M0 numbers mean anything.

legacy_verify(Entry, Options, Verdict) :-
	Entry = entry(Slug, Golden, _, _),
	legacy_stage(Entry, StagedP),
	work_dir(Slug, verify, Dir),
	prepare_dir(Dir),
	file_base_name(StagedP, PBase),
	atomic_list_concat([Dir, '/', PBase], RunP),
	copy_file(StagedP, RunP),
	atom_concat(RunP, '.lpst', GoldenCopy),
	copy_file(Golden, GoldenCopy),
	time_limit(TL),
	run_child(legacy, verify, RunP, Options, TL, Dir, Status, Terms),
	(   Status == success, memberchk(failed_tests(0, _), Terms)
	->  Verdict = pass
	;   Verdict = fail(Status, Terms)
	).

prepare_dir(Dir) :-
	(   exists_directory(Dir)
	->  delete_directory_contents(Dir)
	;   make_directory_path(Dir)
	).

run_child(Engine, Mode, File, Options, TL, Dir, Status) :-
	run_child(Engine, Mode, File, Options, TL, Dir, Status, _).

%	run_child(+EngineDirOrLegacy, +Mode, +File, +Options, +TimeLimit, +Dir, -Status, -Terms)
run_child(legacy, Mode, File, Options, TL, Dir, Status, Terms) :- !,
	legacy_root(EngineDir),
	run_child(EngineDir, Mode, File, Options, TL, Dir, Status, Terms).
run_child(EngineDir, Mode, File, Options, TL, Dir, Status, Terms) :-
	lps2_root(Root),
	atomic_list_concat([Root, '/conformance/child_legacy.pl'], Child),
	atomic_list_concat([Root, '/myswipl.sh'], Swipl),
	atomic_list_concat([Dir, '/status.pl'], StatusFile),
	atomic_list_concat([Dir, '/engine.log'], LogFile),
	ignore(catch(delete_file(StatusFile), _, true)),
	maplist(option_atom, Options, OptionAtoms),
	append([Child, EngineDir, Mode, File, StatusFile, TL], OptionAtoms, Rest),
	% `sh -c 'exec "$0" "$@" ...' swipl arg...` keeps every argument unquoted-safe,
	% which matters: several corpus file names contain spaces.
	append(['-c', 'exec "$0" "$@" >"$LPS2_LOG" 2>&1', Swipl], Rest, ShArgs),
	WallLimit is TL + 30,
	process_create(path(sh), ShArgs,
		       [ process(PID), environment(['LPS2_LOG'=LogFile]) ]),
	(   catch(process_wait(PID, Exit, [timeout(WallLimit)]), _, Exit = exception)
	->  true
	;   Exit = exception
	),
	(   Exit == timeout
	->  catch(process_kill(PID, kill), _, true),
	    catch(process_wait(PID, _, []), _, true),
	    Status = timeout, Terms = []
	;   read_status(StatusFile, Exit, Status, Terms)
	).

option_atom(O, A) :- term_to_atom(O, A).

read_status(StatusFile, Exit, Status, Terms) :-
	(   exists_file(StatusFile),
	    catch(read_file_terms(StatusFile, Terms0), _, fail),
	    memberchk(result(R), Terms0)
	->  Status = R, Terms = Terms0
	;   Status = crashed(Exit), Terms = []
	).

read_file_terms(File, Terms) :-
	setup_call_cleanup(
	    open(File, read, S, [encoding(utf8)]),
	    read_terms_(S, Terms),
	    close(S)).

read_terms_(S, Terms) :-
	read_term(S, T, []),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [T|More],
	    read_terms_(S, More)
	).
