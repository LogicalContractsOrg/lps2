/* open_test.pl — File ▸ Open of other systems' files, as the server sees it.

   The IDE sends every file chosen at once in one `convert` request
   (lps_http.pl, operation "convert" with `files`). This checks that the
   server pairs them the way the example picker and the command line do, that
   a local Inform 7 story converts, that the notes the status line counts are
   at the top of the document, and — with LE2 in this process
   (LPS_LE2_LIB) and the InsurLE translators — that a zipped Daml project
   sent as base64 arrives intact, its choices translated.

   Usage:
     LPS_LE2_LIB=<an LE2 checkout> ./myswipl.sh -q -g "consult('tools/open_test.pl')" -g "opent:main" -t halt
*/

:- module(opent, [main/0]).

:- use_module(library(readutil)).
:- use_module(library(base64)).
:- use_module(library(zip)).
:- use_module(library(filesex)).
:- use_module('../src/edges/lps_http').
:- use_module('../src/syntax/lps_plus', []).
:- use_module('../src/edges/lps_le').

:- dynamic result/2.

main :-
	retractall(result(_, _)),
	pddl_pair,
	drl_with_wording,
	wording_alone,
	local_inform,
	zipped_daml,
	findall(N, result(N, pass), Ps), length(Ps, P),
	findall(N-R, ( result(N, R), R \== pass, R \= skip(_) ), Fs), length(Fs, F),
	forall(result(N, skip(W)), format('skip ~w: ~w~n', [N, W])),
	forall(member(N-R, Fs), format('FAIL ~w: ~q~n', [N, R])),
	format('~n=== File > Open: ~w passed, ~w failed ===~n', [P, F]),
	( F =:= 0 -> true ; halt(1) ).

record(N, R) :- assertz(result(N, R)), format('~w: ~q~n', [N, R]).

example_file(Rel, _{name: Base, source: S}) :-
	module_property(opent, file(Me)), file_directory_name(Me, Tools),
	atomic_list_concat([Tools, '/../examples/', Rel], Path),
	read_file_to_string(Path, S, [encoding(utf8)]),
	file_base_name(Path, B), atom_string(B, Base).

convert(Files, Programs) :-
	lps_http:operation("convert", _{files: Files}, Reply),
	get_dict(programs, Reply, Programs).

%	The field K of a program's reply (fails when it has none).
v(P, K, V) :- get_dict(K, P, V).

%	A domain, a problem of another domain, and the problem of the domain:
%	two programs, the pair and the lone problem.
pddl_pair :-
	maplist(example_file, ['planning/blocks-domain.pddl', 'planning/gripper-p1.pddl', 'planning/blocks-p1.pddl'], Fs),
	convert(Fs, Ps),
	(   length(Ps, 2),
	    member(P1, Ps), v(P1, name, "blocks-p1.lps"), member(P2, Ps), v(P2, name, "gripper-p1.lps"),
	    v(P1, ok, true), v(P1, name, "blocks-p1.lps"), v(P1, origin, "blocks-domain.pddl + blocks-p1.pddl"),
	    v(P1, source, S1), \+ sub_string(S1, _, _, _, "no goal on its own"),
	    v(P2, name, "gripper-p1.lps"), v(P2, source, S2), sub_string(S2, _, _, _, "no actions on its own")
	->  record(pddl_pair, pass)
	;   findall(N-O, ( member(P, Ps), v(P, name, N), v(P, origin, O) ), NOs), record(pddl_pair, got(NOs))
	).

%	The DRL reader is lpsPlus's (src/edges/../syntax/lps_plus.pl): where
%	there is no checkout the door is not there to test.
drl_with_wording :-
	\+ lps_plus:lps_plus_available(drools), !,
	lps_plus:lps_plus_message(drools, M),
	record(drl_with_wording, skip(M)).
drl_with_wording :-
	maplist(example_file, ['migration/drools/drl/fire-alarm.drl', 'migration/drools/drl/fire-alarm.wording'], Fs),
	convert(Fs, Ps),
	Fs = [Drl|_], convert([Drl], [Alone]),
	(   Ps = [P], v(P, ok, true), v(P, origin, "fire-alarm.drl + fire-alarm.wording"),
	    v(P, source, S), v(Alone, source, SA), S \== SA
	->  record(drl_with_wording, pass)
	;   record(drl_with_wording, got(Ps))
	).

wording_alone :-
	example_file('migration/drools/drl/fire-alarm.wording', F),
	convert([F], Ps),
	(   Ps = [P], v(P, ok, false), v(P, error, E), sub_string(E, _, _, _, ".drl")
	->  record(wording_alone, pass)
	;   record(wording_alone, got(Ps))
	).

%	A story from this computer converts as the example does, the notes at
%	the top.
local_inform :-
	example_file('if/inform/BostonCream.ni', F),
	convert([F], Ps),
	(   Ps = [P], v(P, ok, true), v(P, name, Name), sub_string(Name, _, _, 0, ".le"),
	    v(P, diagnostics, Ds), length(Ds, N), N > 0,
	    v(P, source, S), sub_string(S, 0, _, _, "% Converted from BostonCream.ni"),
	    sub_string(S, _, _, _, "the target language is: lps.")
	->  record(local_inform, pass)
	;   record(local_inform, got(Ps))
	).

%	A zipped Daml project, sent as base64: the archive arrives intact, and
%	its choice is a law (not RESIDUE, whatever the server loaded first).
zipped_daml :-
	(   lps_le_call(le_service:le_import_formats(Fs1)) -> Fs0 = Fs1 ; Fs0 = none ),
	(   Fs0 == none
	->  record(zipped_daml, skip('no LE2 in this process (LPS_LE2_LIB)'))
	;   \+ ( member(Fm, Fs0), get_dict(extensions, Fm, Es), member(E, Es), atom_string(zip, E) )
	->  record(zipped_daml, skip('no translator of .zip files (InsurLE extensions)'))
	;   module_property(opent, file(Me)), file_directory_name(Me, Tools),
	    atomic_list_concat([Tools, '/../examples/migration/daml/simple_iou/sources/daml/SimpleIou.daml'], Daml),
	    tmp_file(opent, Zip0), atom_concat(Zip0, '.zip', Zip),
	    setup_call_cleanup(zip_open(Zip, write, Z, []),
			       ( zipper_open_new_file_in_zip(Z, 'simple_iou/daml/SimpleIou.daml', Out, []),
				 read_file_to_codes(Daml, Codes, [type(binary)]),
				 format(Out, '~s', [Codes]), close(Out) ),
			       zip_close(Z)),
	    read_file_to_codes(Zip, ZCodes, [type(binary)]),
	    atom_codes(ZA, ZCodes), base64(ZA, B64),
	    delete_file(Zip),
	    convert([_{name: "simple_iou.zip", base64: B64}], Ps),
	    (   Ps = [P], v(P, ok, true), v(P, source, S),
		sub_string(S, _, _, _, "exercises transfer"),
		\+ sub_string(S, _, _, _, "RESIDUE")
	    ->  record(zipped_daml, pass)
	    ;   record(zipped_daml, got(Ps))
	    )
	).
