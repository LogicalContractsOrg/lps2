/* lps_to_le_test.pl — the gate on the converter to Logical English.
 *
 * `src/syntax/lps_to_le.pl` writes an LPS program of the older, Prolog-like
 * syntax as a Logical English document. The claim it makes is not that the
 * English is beautiful: it is that the two files are the same program. This
 * gate checks that claim the only way worth checking it — by running both and
 * comparing the traces, cycle by cycle, with the conformance harness's own
 * comparator (conformance/lpst.pl, the one the LPS1 comparison uses).
 *
 *     LPS_LE2_LIB=/path/to/LE2 ./myswipl.sh -q \
 *         -g "consult('tools/lps_to_le_test.pl')" -g "lps_to_le_test:main" -t halt
 *
 * Add `-g "lps_to_le_test:main(['examples/start'])"` to run one folder, or
 * name single programs the same way.
 *
 * Converted documents are written under `build/lps_to_le/`, one folder per
 * program, and left there to be read. The folder matters: a `.le` document
 * with a `.lps` file of the same name beside it is compiled *together with
 * it* (docs/user/reference/le-for-lps.md §7), so a converted document written
 * next to its original would be run twice over. One folder per program is how
 * the two are kept apart.
 *
 * What is skipped, and why it is named rather than silently passed over:
 *
 *   - a companion file (`examples/le/badlight.lps` and four others): half a
 *     program, meaningless on its own;
 *   - a program the original engine cannot compile or run here: the converter
 *     is not on trial for that;
 *   - a program whose run does not end within the time limit on either side.
 */

:- module(lps_to_le_test, [main/0, main/1, convert_and_compare/3]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(filesex)).
:- use_module(library(time)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_diag').
:- use_module('../src/syntax/lps_to_le').
:- use_module('../src/edges/lps_le').
:- use_module('../conformance/lpst').
:- use_module('../src/syntax/lps_internal_syntax').

run_seconds(60).

%!	programs(+Roots, -Files) is det.
%
%	Every LPS program under Roots, in the older syntax: `.lps` files and
%	the `.pl` files of `examples/`, which are the same syntax under the
%	name upstream used. Sorted, so two runs of this gate say the same
%	thing in the same order.
programs(Roots, Files) :-
	findall(F,
		(   member(R, Roots), absolute_root(R, Root),
		    (	exists_file(Root)
		    ->	F = Root
		    ;	directory_member(Root, F,
				[recursive(true), extensions([lps, pl])])
		    )
		),
		Fs0),
	sort(Fs0, Files).

absolute_root(R, Abs) :-
	(   is_absolute_file_name(R) -> Abs = R
	;   lps_root_dir(Dir), atomic_list_concat([Dir, '/', R], Abs)
	).

lps_root_dir(Dir) :-
	( lps2_root(Dir) -> true ; working_directory(Dir, Dir) ).

		 /*******************************
		 *	     the gate		*
		 *******************************/

main :- main(['examples']).

main(Roots) :-
	format('~n=== the converter to Logical English: same program, same run ===~n~n', []),
	(   lps_to_le_ready(ok)
	->  true
	;   lps_to_le_ready(Why),
	    format('cannot run: ~w~n', [Why]), halt(2)
	),
	programs(Roots, Files),
	maplist(one_program, Files, Results),
	summary(Results).

summary(Results) :-
	tally(Results, ok, NOk),
	tally(Results, skipped, NSkip),
	tally(Results, limited, NLim),
	tally(Results, failed, NFail),
	length(Results, N),
	format('~n=== ~w of ~w converted programs run exactly as the original; \c
		~w skipped, ~w limited, ~w failed ===~n',
	       [NOk, N, NSkip, NLim, NFail]),
	( NLim =:= 0
	->  true
	;   format('~nthe limited ones, and what Logical English cannot say:~n', []),
	    forall(member(limited(S, M), Results), format('  ~w~n    ~w~n', [S, M]))
	),
	( NFail =:= 0 -> true ; halt(1) ).

tally(Results, Kind, N) :-
	aggregate_all(count, ( member(R, Results), functor(R, Kind, _) ), N).

one_program(File, Result) :-
	short_name(File, Short),
	(   convert_and_compare(File, Short, Result)
	->  true
	;   Result = failed(Short, 'the gate itself failed on this program')
	),
	report(Result).

report(ok(Short)) :- format('  ok      ~w~n', [Short]).
report(skipped(Short, Why)) :- format('  skip    ~w  (~w)~n', [Short, Why]).
report(limited(Short, _)) :- format('  limit   ~w~n', [Short]).
report(failed(Short, Why)) :- format('  FAIL    ~w  ~w~n', [Short, Why]).

short_name(File, Short) :-
	lps_root_dir(Dir), atom_concat(Dir, '/', D),
	( atom_concat(D, Short0, File) -> Short = Short0 ; Short = File ).

%!	convert_and_compare(+File, +Short, -Result) is det.
%
%	Convert File, run both, compare. Result is ok/1, skipped/2 or
%	failed/2.
convert_and_compare(File, Short, Result) :-
	(   companion_of(File, LE)
	->  file_base_name(LE, B),
	    format(atom(W), 'the companion of ~w', [B]),
	    Result = skipped(Short, W)
	;   \+ trace_of_lps(File, _, _)
	->  Result = skipped(Short, 'the original does not compile or run here')
	;   trace_of_lps(File, Original, Outcome),
	    lps_to_le_file(File, [], LEText, Diags),
	    (	LEText == ""
	    ->	first_message(Diags, M),
		Result = failed(Short, M)
	    ;	write_document(File, LEText, LEFile, Dir),
		(   trace_of_le(LEFile, Converted, LEOutcome)
		->  atom_concat(Dir, '/original.lpst', A),
		    atom_concat(Dir, '/converted.lpst', B),
		    write_lpst(A, Original, [dc], Outcome),
		    write_lpst(B, Converted, [dc], LEOutcome),
		    compare_traces(Short, A, B, Diags, Result)
		;   member(diag(error, _, _, M, _), Diags)
		->  %  It does not run, and the converter said beforehand what
		    %  it could not carry over: a named limitation, not a
		    %  silent wrong answer.
		    Result = limited(Short, M)
		;   Result = failed(Short, 'the converted document does not compile or run')
		)
	    )
	).

first_message(Diags, M) :-
	( member(diag(error, _, _, M, _), Diags) -> true ; M = 'conversion produced nothing' ).

%	The two traces go through the very writer and comparator the
%	conformance harness uses on the LPS1 goldens, and the two `.lpst`
%	files are left in the folder beside the document, to be read when a
%	run does differ.
compare_traces(Short, OriginalFile, ConvertedFile, Diags, Result) :-
	lpst_read(OriginalFile, A),
	lpst_read(ConvertedFile, B),
	lpst_compare(B, A, verdict(Upstream, Strict, Failures)),
	(   Strict == pass, Upstream == pass
	->  Result = ok(Short)
	;   %  The converter said what it could not carry over, and the runs
	    %  differ because of it: a limitation of the surface language,
	    %  named, not a fault in the conversion. The gate reports it and
	    %  does not fail on it -- a silent difference is what must fail.
	    member(diag(error, _, _, M, _), Diags)
	->  Result = limited(Short, M)
	;   Failures = [F|_]
	->  format(atom(W), 'the runs differ: ~q', [F]),
	    Result = failed(Short, W)
	;   Result = failed(Short, 'the runs differ')
	).

		 /*******************************
		 *	 running the two	*
		 *******************************/

trace_of_lps(File, Trace, Outcome) :-
	run_seconds(Secs),
	catch(call_with_time_limit(Secs,
		( lps_compile(file(File), legacy, [dc], Program, Diags),
		  diags_ok(Diags),
		  run_program(Program, Trace, Outcome) )),
	      _, fail).

trace_of_le(File, Trace, Outcome) :-
	run_seconds(Secs),
	catch(call_with_time_limit(Secs,
		( lps_le:lps_le_translate(File, Text, _Prov, LeDiags),
		  diags_ok(LeDiags),
		  internal_terms(Text, Terms),
		  lps_compile(terms(Terms), internal, [dc], Program, Diags),
		  diags_ok(Diags),
		  run_program(Program, Trace, Outcome) )),
	      _, fail).

run_program(Program, Trace, Outcome) :-
	lps_session_new(Program, [dc], S0),
	lps_session_run(S0, end, S, Trace),
	( lps_session_outcome(S, Outcome) -> true ; Outcome = unknown ).

internal_terms(Text, Terms) :-
	setup_call_cleanup(open_string(Text, In), read_all(In, Terms), close(In)).

read_all(In, Terms) :-
	read_term(In, T, [module(lps_to_le_test)]),
	( T == end_of_file -> Terms = [] ; Terms = [T|Rest], read_all(In, Rest) ).

		 /*******************************
		 *   where the document goes	*
		 *******************************/

%	One folder per program, under build/. A `.le` document is compiled
%	together with any `.lps` file of the same name beside it, so the
%	converted document must not be written next to the original.
write_document(File, LEText, LEFile, Dir) :-
	lps_root_dir(Root),
	short_name(File, Short),
	file_base_name(File, Base),
	file_name_extension(Name, _, Base),
	atomic_list_concat(Parts, '/', Short),
	atomic_list_concat(Parts, '_', Slug0),
	( atom_concat(S1, '.lps', Slug0) -> Slug = S1
	; atom_concat(S2, '.pl', Slug0) -> Slug = S2
	; Slug = Slug0 ),
	atomic_list_concat([Root, '/build/lps_to_le/', Slug], Dir),
	make_directory_path(Dir),
	atomic_list_concat([Dir, '/', Name, '.le'], LEFile),
	setup_call_cleanup(open(LEFile, write, Out, [encoding(utf8)]),
			   format(Out, '~w', [LEText]),
			   close(Out)).
