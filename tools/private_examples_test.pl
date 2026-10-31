/* private_examples_test.pl — the unlisted examples of examples/private/.

   An example under examples/private/ opens by its exact name, and a folder
   under private/ shows on the start page to whoever names it
   (`/?dir=private/<folder>`); nothing lists it: not the start page's tree,
   not the picker's list, not the examples' search; `/?dir=private` alone
   shows nothing; the static build does not carry it
   (lps_api:private_example_dir/1, examples/private/README.md).

   The folder is lpsPlus's examples/private/ (lps_api:private_example_full/2);
   the test writes its own private examples there and removes them
   afterwards, and skips with no lpsPlus.

   Usage:
     ./myswipl.sh -q -g "consult('tools/private_examples_test.pl')" -g "privex:main" -t halt
*/

:- module(privex, [main/0]).

:- use_module(library(filesex)).
:- use_module(library(apply)).
:- use_module(library(yall)).
:- use_module('../src/edges/lps_http').
:- use_module('../wasm/pack').

main :-
	(   lps_api:private_example_full('examples/private/zz_privex_test', Dir)
	->  main(Dir)
	;   format('~n=== private examples: skipped (no lpsPlus, so no examples/private/) ===~n', [])
	).

main(Dir) :-
	atomic_list_concat([Dir, '/privexprogram.lps'], File),
	atomic_list_concat([Dir, '/privexdoc.le'], LEFile),
	setup_call_cleanup(
	    ( make_directory_path(Dir),
	      setup_call_cleanup(open(File, write, S),
				 format(S, "% The private examples' test program~nfluents f.~ninitially f.~n", []),
				 close(S)),
	      %  a document for LPS, which lpsPlus's other examples would list
	      %  (lps_api:plus_example_dir/2)
	      setup_call_cleanup(open(LEFile, write, S2),
				 format(S2, "the target language is: lps.~n", []),
				 close(S2)) ),
	    findall(Name-Ok, ( check(Name, G), ( catch(G, _, fail) -> Ok = ok ; Ok = 'FAIL' ) ), Rs),
	    delete_directory_and_contents(Dir)),
	forall(member(N-O, Rs), format('  ~w  ~w~n', [O, N])),
	include([_-O]>>(O \== ok), Rs, Bad),
	length(Rs, NR), length(Bad, NB), NOK is NR - NB,
	format('~n=== private examples: ~w of ~w checks ===~n', [NOK, NR]),
	( NB =:= 0 -> true ; halt(1) ).

check('opens by its exact name',
      lps_api:example_source('private/zz_privex_test/privexprogram', "privexprogram.lps", _)).
check('a document of the folder opens by name too',
      lps_api:example_source('private/zz_privex_test/privexdoc.le', "privexdoc.le", _)).
check('not in the picker''s list',
      ( lps_api:example_list(Es), \+ ( member(E, Es), get_dict(name, E, EN), sub_atom(EN, _, _, _, 'privex') ) )).
check('no folder of private/ listed',
      ( lps_api:example_folders(Fs), \+ ( member(F, Fs), get_dict(dirpath, F, FD), sub_atom(FD, 0, _, _, 'examples/private') ) )).
check('not in the start page''s tree',
      ( lps_http:example_tree(T), \+ ( sub_term(X, T), atom(X), sub_atom(X, _, _, _, 'private/') ) )).
check('not found by the examples'' search',
      ( lps_examples_search:examples_search("privexprogram", [], H), H == [] )).
check('?dir=private/<folder> shows the folder',
      ( lps_api:private_example_tree(zz_privex_test, folder(_, _, Cs)),
	memberchk(leaf('private/zz_privex_test/privexprogram', _), Cs) )).
check('?dir=private shows nothing',
      \+ lps_api:private_example_tree('', _)).
check('?dir=private/../x leaves nothing',
      \+ lps_api:private_example_tree('../start', _)).
check('not in the static build',
      ( lps_wasm_pack:payload_files(Ps), \+ ( member(P, Ps), sub_atom(P, 0, _, _, 'examples/private/') ) )).
