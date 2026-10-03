/* examples_search_test.pl — the examples' search (src/edges/lps_examples_search.pl):
   by name, by declaration and through the text, and the operation the picker
   and the start page ask.

   Usage:
     ./myswipl.sh -q -g run_tests -t halt tools/examples_search_test.pl
*/

:- module(examples_search_test, []).

:- use_module(library(plunit)).
:- use_module('../src/edges/lps_api').
:- use_module('../src/edges/lps_examples_search').

names(Hits, Names) :- findall(N, ( member(H, Hits), atom_string(N, H.name) ), Names).

:- begin_tests(examples_search).

test(by_name) :-
    examples_search("goat", [scope(name)], Hits),
    names(Hits, Names),
    assertion(memberchk('start/goat_declarative', Names)).

%   A declaration search finds the programs that declare the fluent, with the
%   declaration's own line as the snippet.
test(by_declaration) :-
    examples_search("loc", [scope(templates)], Hits),
    names(Hits, Names),
    assertion(memberchk('start/goat_declarative', Names)),
    member(H, Hits), atom_string(HN, H.name), HN == 'start/goat_declarative', !,
    assertion(H.field == templates),
    assertion(sub_string(H.snippet, _, _, _, "fluents")).

test(phrase_must_occur) :-
    examples_search("\"wolf goat cabbage\"", [], Hits),
    names(Hits, Names),
    assertion(Names \== []),
    examples_search("\"cabbage goat wolf farmer\"", [], None),
    assertion(None == []).

test(empty_query_and_cached_index) :-
    examples_search("", [], Hits), assertion(Hits == []),
    examples_index_size(N), assertion(N > 50),
    statistics(cputime, T0), examples_search("goat", [], _), statistics(cputime, T1),
    assertion(T1 - T0 < 2).

test(lps_declaration_lines) :-
    declaration_lines(pl, "maxTime(5).\nfluents loc(_, _),\n  carrying(_).\nevents row(_, _).\nactions go(_).\ninitially loc(a).\nobserve go(x) from 1 to 2.\n", Lines),
    assertion(Lines == ["fluents loc(_, _),", "carrying(_).", "events row(_, _).", "actions go(_)."]).

test(le_declaration_lines) :-
    declaration_lines(le, "the target language is: lps.\n\nthe templates are:\n*a light* is on.\n\nthe fluents are:\n*a light* is on.\n\nthe knowledge base k includes:\nwhen x then y.\n", Lines),
    assertion(Lines == ["*a light* is on.", "*a light* is on."]).

test(operation) :-
    lps_api:operation("search_examples", _{query: "goat", scope: "name"}, R),
    assertion(R.ok == true),
    names(R.hits, Names),
    assertion(memberchk('start/goat_declarative', Names)).

%   The index the build writes (write_index/0) is read back instead of built.
test(prebuilt_index_is_read, [setup(( lps_examples_search:index_file(F), ( exists_file(F) -> delete_file(F) ; true ) )),
                              cleanup(( lps_examples_search:index_file(F), ( exists_file(F) -> delete_file(F) ; true ) ))]) :-
    write_index,
    lps_examples_search:index_file(File),
    assertion(exists_file(File)),
    retractall(lps_examples_search:index_cache(_, _)),
    statistics(cputime, T0),
    examples_search("goat", [scope(name)], Hits),
    statistics(cputime, T1),
    names(Hits, Names),
    assertion(memberchk('start/goat_declarative', Names)),
    assertion(T1 - T0 < 1.5).

:- end_tests(examples_search).
