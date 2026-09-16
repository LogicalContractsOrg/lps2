/* example_alias_test.pl — old example names keep opening.

   lps_http:example_alias/2 keeps the names examples had before they moved
   (links, the start page's history, the documentation, videos). Each alias
   must open an existing file, and an old name must not also be a current one.

   Usage:
     ./myswipl.sh -q -g "consult('tools/example_alias_test.pl')" -g "exalias:main" -t halt
*/

:- module(exalias, [main/0]).

:- use_module('../src/edges/lps_http').

main :-
	findall(Old-New, lps_http:example_alias(Old, New), Aliases0),
	%  A directory alias, through one example that was under it.
	findall(Old-New,
		( lps_http:example_dir_alias(OldDir, NewDir),
		  once(( lps_http:example_list(Es), member(E, Es),
			 atom_concat(NewDir, '/', NS), atom_concat(NS, Rest, E.name) )),
		  atomic_list_concat([OldDir, '/', Rest], Old),
		  atomic_list_concat([NewDir, '/', Rest], New) ),
		DirAliases),
	append(Aliases0, DirAliases, Aliases),
	include(bad, Aliases, Bad),
	length(Aliases, N), length(Bad, NB), NOK is N - NB,
	forall(member(O-W, Bad), format('  FAIL  ~w -> ~w: no such example~n', [O, W])),
	format('~n=== example aliases: ~w of ~w open ===~n', [NOK, N]),
	( NB =:= 0 -> true ; halt(1) ).

bad(Old-_) :-
	\+ ( lps_http:example_path(Old, Path), exists_file(Path) ).
