/* example_readmes_test.pl — the READMEs of the example folders lead somewhere.

   A folder's README is read on the start page, in a panel beside the list of
   examples (src/edges/readme_panel.js), and its links open the programs it
   names. For every README under examples/ this checks that it starts with a
   `# ` title (the start page labels the folder from it), that each relative
   link names a file or folder that exists, and that each link to the
   manual (`/docs/user/<page>`) names a page that exists. It also checks
   that the number of examples the "Learning LPS" tutorial states is the
   number the server lists (lps_api:example_list/1), which had drifted
   (289 against 294) by September 2026.

   Usage:
     ./myswipl.sh -q -g "consult('tools/example_readmes_test.pl')" -g "exreadme:main" -t halt
*/

:- module(exreadme, [main/0]).

:- use_module(library(pcre)).
:- use_module(library(lists)).
:- use_module(library(filesex)).
:- use_module('../src/edges/lps_api').

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

%	"lists all N programs — M of LPS1's own" in the tutorial, against the list.
tutorial_count_problem('docs/user/tutorials/lps-tutorial.md', Msg) :-
	read_file_to_string('docs/user/tutorials/lps-tutorial.md', Text, [encoding(utf8)]),
	(   re_matchsub("lists all (?<all>\\d+) programs — (?<corpus>\\d+) of LPS1's own", Text, Sub, [])
	->  number_string(All, Sub.all), number_string(Corpus, Sub.corpus),
	    lps_api:example_list(Es),
	    length(Es, NAll),
	    include([E]>>( get_dict(dirpath, E, D), sub_atom(D, 0, _, _, legacy_lps1) ), Es, Cs),
	    length(Cs, NCorpus),
	    (All-Corpus) \== (NAll-NCorpus),
	    format(atom(Msg), 'states ~w programs, ~w of LPS1; the server lists ~w, ~w of LPS1',
		   [All, Corpus, NAll, NCorpus])
	;   Msg = 'the sentence giving the number of examples was not found'
	).

main :-
	findall(F, readme(F), Files),
	findall(F-M, ( member(F, Files), problem(F, M) ), Problems0),
	findall(F-M, tutorial_count_problem(F, M), CountProblems),
	append(Problems0, CountProblems, Problems),
	forall(member(F-M, Problems), format('  FAIL  ~w: ~w~n', [F, M])),
	length(Files, N), length(Problems, NP),
	format('~n=== example READMEs: ~w READMEs, ~w problems ===~n', [N, NP]),
	( NP =:= 0 -> true ; halt(1) ).
