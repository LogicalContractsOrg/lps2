/* sector_page_test.pl — the sector pages lead somewhere.

   A sector page (src/pages/<sector>.html, served at /<sector> by
   lps_http:sector_page/2) is what a printed leaflet's QR code opens, so a
   broken one is found by a prospect, not by us. For every page: it has a
   route; its drawing is in it (lpsPlus's leaflets/build.cjs writes it between
   two marks, and a page committed before that ran has none); every document
   of this server it links to exists, and every example it opens.  Links to
   other servers are listed, not fetched: the gate runs without a network.

   Usage:
     ./myswipl.sh -q -g "consult('tools/sector_page_test.pl')" -g "sector_test:main" -t halt
*/

:- module(sector_test, [main/0]).

:- use_module(library(http/http_dispatch)).
:- use_module(library(pcre)).
:- use_module('../src/edges/lps_http').

main :-
	lps_api:lps_root(Root),
	atomic_list_concat([Root, '/src/pages/*.html'], Pattern),
	expand_file_name(Pattern, Files),
	findall(F-Problem, ( member(F, Files), problem(F, Problem) ), Problems),
	forall(member(F-P, Problems),
	       ( file_base_name(F, B), format('  FAIL  ~w: ~w~n', [B, P]) )),
	length(Files, N), length(Problems, NP),
	format('~n=== sector pages: ~w page(s), ~w problem(s) ===~n', [N, NP]),
	( NP =:= 0 -> true ; halt(1) ).

problem(File, no_route(Path)) :-
	file_base_name(File, Base), file_name_extension(Sector, html, Base),
	atom_concat('/', Sector, Path),
	\+ ( http_current_handler(Path, _:Closure), Closure = sector_page(Sector) ).
problem(File, no_drawing) :-
	read_file_to_string(File, S, [encoding(utf8)]),
	\+ re_match("<!-- diagram:begin[^>]*-->\\s*(<style>[\\s\\S]*?</style>\\s*)?<svg[\\s\\S]*</svg>\\s*<!-- diagram:end -->", S).
problem(File, no_head_for_telemetry) :-
	read_file_to_string(File, S, [encoding(utf8)]),
	\+ sub_string(S, _, _, _, "<head>").
problem(File, Problem) :-
	read_file_to_string(File, S, [encoding(utf8)]),
	re_foldl([M, L0, [X|L0]]>>get_dict(1, M, X), "href=\"([^\"]+)\"", S, [], Hs0, []),
	sort(Hs0, Hs),
	member(Href0, Hs), atom_string(Href, Href0),
	link_problem(Href, Problem).

link_problem(Href, no_such_document(Href)) :-
	atom_concat('/docs/', Rest0, Href),
	( sub_atom(Rest0, B, _, _, '#') -> sub_atom(Rest0, 0, B, _, Rest) ; Rest = Rest0 ),
	lps_api:lps_root(Root),
	atomic_list_concat([Root, '/docs/', Rest, '.md'], File),
	\+ ( lps_http:public_doc(Rest), exists_file(File) ).
link_problem(Href, no_such_example(Name)) :-
	atom_concat('/ide?example=', Name, Href),
	\+ ( lps_api:example_path(Name, Path), exists_file(Path) ).
