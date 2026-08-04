/* adapter_lps2.pl — engine adapter for LPS2.

   Same contract as adapter_legacy.pl, so runner.pl can drive either engine
   over the same corpus and compare with the same code. The staged program
   comes from adapter_legacy:legacy_stage/2 — that is deliberate: the entry
   must be *the same bytes* both engines see, including psyntax's regeneration
   of the `_.P` from its source, or the comparison measures the staging rather
   than the engine.

   LPS2 never writes inside legacy_lps1/ (hard rule 1) because it works on
   the staged copy under build/work/<slug>/<variant>/, exactly as the legacy
   adapter does.
*/

:- module(adapter_lps2, [
	lps2_run/4,              % +Entry, +Variant, +Options, -Result
	lps2_dump/3              % +SourceFile, +WorkDir, -Result
	]).

:- use_module(library(filesex)).
:- use_module(library(process)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(corpus).
:- use_module(lpst).
:- use_module(perturb).
:- use_module(adapter_legacy).

%!	lps2_run(+Entry, +Variant, +Options, -Result) is det.
%
%	Result = run(Status, Trace, Seconds), Status one of
%	success/failed/error(E)/timeout/no_trace.
lps2_run(Entry, Variant, Options, run(Status, Trace, Seconds)) :-
	Entry = entry(Slug, _Golden, _P, _Src),
	legacy_stage(Entry, StagedP),
	lps2_work_dir(Slug, Variant, Dir),
	prepare_dir(Dir),
	file_base_name(StagedP, PBase),
	atomic_list_concat([Dir, '/', PBase], RunP),
	perturb_program(Variant, StagedP, RunP),
	get_time(T0),
	time_limit(TL),
	run_child(run, RunP, Options, TL, Dir, Status0),
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

%!	lps2_dump(+SourceFile, +WorkDir, -Result) is det.
%
%	The M2 gate: translate surface syntax to the internal representation and
%	write it out, so it can be diffed against psyntax's `_.P`.
lps2_dump(SourceFile, Dir, Result) :-
	time_limit(TL),
	run_child(dump, SourceFile, [dc], TL, Dir, Result).

lps2_work_dir(Slug, Variant, Dir) :-
	lps2_root(Root),
	atomic_list_concat([Root, '/build/work/', Slug, '/lps2_', Variant], Dir).

prepare_dir(Dir) :-
	(   exists_directory(Dir)
	->  delete_directory_contents(Dir)
	;   make_directory_path(Dir)
	).

run_child(Mode, File, Options, TL, Dir, Status) :-
	lps2_root(Root),
	atomic_list_concat([Root, '/conformance/child_lps2.pl'], Child),
	atomic_list_concat([Root, '/myswipl.sh'], Swipl),
	atomic_list_concat([Dir, '/status.pl'], StatusFile),
	atomic_list_concat([Dir, '/engine.log'], LogFile),
	ignore(catch(delete_file(StatusFile), _, true)),
	maplist(option_atom, Options, OptionAtoms),
	append([Child, Root, Mode, File, StatusFile, TL], OptionAtoms, Rest),
	%  `sh -c 'exec "$0" "$@" ...'` keeps every argument unquoted-safe, which
	%  matters: several corpus file names contain spaces.
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
	    Status = timeout
	;   read_status(StatusFile, Exit, Status)
	).

option_atom(O, A) :- term_to_atom(O, A).

read_status(StatusFile, Exit, Status) :-
	(   exists_file(StatusFile),
	    catch(read_file_terms(StatusFile, Terms), _, fail),
	    memberchk(result(R), Terms)
	->  Status = R
	;   Status = crashed(Exit)
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
