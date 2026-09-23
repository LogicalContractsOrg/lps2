/* example_readmes_test.pl — the READMEs of the example folders lead somewhere.

   A folder's README is read on the start page, in a panel beside the list of
   examples (src/edges/readme_panel.js), and its links open the programs it
   names. For every README under examples/ this checks that it starts with a
   `# ` title (the start page labels the folder from it), that each relative
   link names a file or folder that exists, and that each link to the
   manual (`/docs/user/<page>`) names a page that exists.

   Usage:
     ./myswipl.sh -q -g "consult('tools/example_readmes_test.pl')" -g "exreadme:main" -t halt
*/

:- module(exreadme, [main/0]).

:- use_module(library(pcre)).
:- use_module(library(lists)).
:- use_module(library(filesex)).

readme(File) :-
	directory_member(examples, File, [recursive(true), matches('README.md')]),
	\+ sub_atom(File, _, _, _, 'node_modules'),
	\+ sub_atom(File, _, _, _, '/sources/').

%	The links of a README, as written, without their query or fragment.
link(File, Target) :-
	read_file_to_string(File, Text, [encoding(utf8)]),
	re_foldl([M, L0, [U|L0]]>>get_dict(1, M, U), "\\]\\(([^)\\s]+)\\)", Text, [], Us, []),
	member(U0, Us),
	atom_string(U, U0),
	( sub_atom(U, B, _, _, '#') -> sub_atom(U, 0, B, _, U1) ; U1 = U ),
	( sub_atom(U1, B2, _, _, '?') -> sub_atom(U1, 0, B2, _, Target) ; Target = U1 ),
	Target \== ''.

problem(File, 'does not start with "# "') :-
	setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
			   read_line_to_string(In, Line), close(In)),
	\+ ( string(Line), sub_string(Line, 0, 2, _, "# ") ).
problem(File, Msg) :-
	link(File, Target),
	\+ re_match("^[a-z]+:"/i, Target),
	(   atom_concat('/docs/user/', Page, Target)
	->  atomic_list_concat(['docs/user/', Page, '.md'], Path),
	    \+ exists_file(Path),
	    format(atom(Msg), 'no such manual page: ~w', [Target])
	;   sub_atom(Target, 0, 1, _, '/')
	->  fail
	;   file_directory_name(File, Dir),
	    directory_file_path(Dir, Target, Path0),
	    ( sub_atom(Path0, _, 1, 0, '/') -> sub_atom(Path0, 0, _, 1, Path) ; Path = Path0 ),
	    \+ exists_file(Path), \+ exists_directory(Path),
	    format(atom(Msg), 'no such file or folder: ~w', [Target])
	).

main :-
	findall(F, readme(F), Files),
	findall(F-M, ( member(F, Files), problem(F, M) ), Problems),
	forall(member(F-M, Problems), format('  FAIL  ~w: ~w~n', [F, M])),
	length(Files, N), length(Problems, NP),
	format('~n=== example READMEs: ~w READMEs, ~w problems ===~n', [N, NP]),
	( NP =:= 0 -> true ; halt(1) ).
