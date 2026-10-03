/*  lps_examples_search.pl — the examples' search: by name, by declaration,
    or through the text.

    "Open example from server" and the start page's search box ask here, as
    LE2's le_examples_search.pl answers the Logical English editor; the two
    modules take the same shape and the same words (lps_docs_search.pl's
    words/2: folded, without accents, stemmed), and differ in what counts as a
    declaration. A query is a few words, or a phrase in quotes, and a scope:
    the names (the program's path and its title, its first comment), the
    declarations (`fluents`, `events` and `actions` in an LPS program; the
    templates, fluents, events and the other declaration sections of a
    Logical English document), the text (everything), or all three, the
    default. Every word must occur in the scope; a program scores by the
    words it has, each weighted by how rare it is among the examples, and a
    name counts for more than a declaration, a declaration for more than a
    line of text.

    The index is a Prolog term: for each program, the set of the words of
    each field. The deployment's build writes it (`write_index/0`: the
    Dockerfile and wasm/build.sh, to `examples/search-index.fast`, a
    fast-term file that is not committed), and the first search reads it in
    a few milliseconds, provided the files it was built from are the ones
    present (their paths, relative to this repository, and their sizes are
    its stamp). Without the file it is built on the spot, in a few seconds,
    and kept in the process; either way it is rebuilt when a file changes.
    Phrases and the line shown with a hit are read from the hit's own file.
    Paths in the index are relative to the repository, so an index written
    on one machine is read on another. */

:- module(lps_examples_search, [
    examples_search/3,          % +Query, +Options, -Hits
    examples_index_size/1,      % -N
    write_index/0,              % the deployment's build
    write_index/2,              % +File, +Options
    declaration_lines/3         % +Extension, +Text, -Lines
]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(ordsets)).
:- use_module(library(readutil)).
:- use_module(lps_docs_search, [words/2, parse_query/3]).

:- dynamic index_cache/2.       % Stamp, Index

%!  examples_search(+Query, +Options, -Hits) is det.
%
%   Hits: dicts {name, title, field, snippet, score}, best first. Options:
%   scope(all|name|templates|text) (default all; `templates` is the
%   declarations), limit(N) (default 40).
examples_search(Query, Options, Hits) :-
    option_(scope(Scope), Options, all),
    option_(limit(Limit), Options, 40),
    parse_query(Query, Terms, Phrases),
    (   Terms == [], Phrases == []
    ->  Hits = []
    ;   index(index(N, DF, Entries)),
        maplist(term_weight(N, DF), Terms, Weights),
        pairs_keys_values(TW, Terms, Weights),
        scope_fields(Scope, Fields),
        findall(Score-Hit,
                ( member(E, Entries),
                  listable(E),
                  entry_hit(E, Fields, TW, Phrases, Score, Hit) ),
                Scored0),
        keysort(Scored0, Scored1), reverse(Scored1, Scored),
        take(Limit, Scored, Taken),
        findall(_{name: Name, title: Title, field: Field, snippet: Snippet, score: S},
                ( member(S-hit(Name, Rel, Title, Field, TLines), Taken),
                  snippet(Field, TW, Phrases, Title, TLines, Rel, Snippet) ),
                Hits)
    ).

option_(Opt, Options, _) :- memberchk(Opt, Options), !.
option_(Opt, _, Default) :- arg(1, Opt, Default).

take(_, [], []) :- !.
take(0, _, []) :- !.
take(N, [X|Xs], [X|Ys]) :- N1 is N - 1, take(N1, Xs, Ys).

term_weight(N, DF, Term, W) :-
    ( memberchk(Term-D, DF) -> true ; D = 0 ),
    W is log(1 + N / (D + 1)).

scope_fields(name,      [name-3]).
scope_fields(templates, [templates-2]).
scope_fields(text,      [text-1]).
scope_fields(all,       [name-3, templates-2, text-1]).

%   A `.drl` is listed only where the Drools reader is loaded for this
%   visitor (lps_api.pl, example_list/1): the search answers the same.
listable(ex(_, Rel, _, _, _, _, _)) :-
    file_name_extension(_, Ext, Rel),
    ( Ext == drl -> lps_plus:lps_plus_available(drools) ; true ).

%   An entry is a hit when every term occurs in one of the fields, and every
%   phrase occurs, in order, in one of them (read from the file: the index
%   holds sets of words, not their order); it scores by each term's weight
%   times the boost of the best field that has it, and is reported under
%   that best field.
entry_hit(ex(Name, Rel, Title, FW, TW, XW, TLines), Fields, Terms, Phrases, Score, hit(Name, Rel, Title, Field, TLines)) :-
    term_scores(Terms, Fields, FW, TW, XW, Scores, BestFields),
    length(Terms, NT), length(Scores, NT),
    Scores \== [],
    phrases_occur(Phrases, Fields, Name, Title, TLines, Rel),
    sum_list(Scores, Score),
    best_field(BestFields, Field).

term_scores([], _, _, _, _, [], []).
term_scores([T-W|Ts], Fields, FW, TW, XW, Scores, Bests) :-
    findall(B-F, ( member(F-B, Fields), field_set(F, FW, TW, XW, Set), ord_memberchk(T, Set) ), BFs),
    (   BFs == []
    ->  Scores = Scores1, Bests = Bests1
    ;   max_member(B-F, BFs),
        S is W * B,
        Scores = [S|Scores1], Bests = [F|Bests1]
    ),
    term_scores(Ts, Fields, FW, TW, XW, Scores1, Bests1).

field_set(name, FW, _, _, FW).
field_set(templates, _, TW, _, TW).
field_set(text, _, _, XW, XW).

best_field(Fields, Best) :-
    ( memberchk(name, Fields) -> Best = name
    ; memberchk(templates, Fields) -> Best = templates
    ; Best = text ).

phrases_occur([], _, _, _, _, _) :- !.
phrases_occur(Phrases, Fields, Name, Title, TLines, Rel) :-
    findall(F-Seq, ( member(F-_, Fields), field_sequence(F, Name, Title, TLines, Rel, Seq) ), Seqs),
    forall(member(P, Phrases), ( member(_-Seq, Seqs), sublist_(P, Seq) )).

field_sequence(name, Name, Title, _, _, Seq) :- name_words(Name, Title, Seq).
field_sequence(templates, _, _, TLines, _, Seq) :- atomic_list_concat(TLines, ' ', T), words(T, Seq).
field_sequence(text, _, _, _, Rel, Seq) :- file_text(Rel, Text), words(Text, Seq).

sublist_(P, L) :- append(_, R, L), append(P, _, R), !.

snippet(name, Terms, Phrases, Title, TLines, Rel, Snippet) :- !,
    (   Title \== "" -> Snippet = Title
    ;   snippet(text, Terms, Phrases, Title, TLines, Rel, Snippet)
    ).
snippet(templates, Terms, Phrases, _, TLines, _, Snippet) :- !,
    first_line_with(Terms, Phrases, TLines, Snippet).
snippet(text, Terms, Phrases, _, _, Rel, Snippet) :-
    file_text(Rel, Text),
    split_string(Text, "\n", "\r", Lines),
    first_line_with(Terms, Phrases, Lines, Snippet).

first_line_with(Terms, Phrases, Lines, Snippet) :-
    pairs_keys(Terms, Ws0),
    findall(W, member([W|_], Phrases), Ws1),
    append(Ws0, Ws1, Ws),
    (   member(Line, Lines),
        words(Line, LW),
        member(W, Ws), memberchk(W, LW)
    ->  normalize_space(string(S0), Line),
        ( string_length(S0, L), L > 160 -> sub_string(S0, 0, 157, _, S1), string_concat(S1, "…", Snippet)
        ; Snippet = S0 )
    ;   Snippet = ""
    ).

file_text(Rel, Text) :-
    absolute_of(Rel, File),
    catch(read_file_to_string(File, Text, [encoding(utf8)]), _, Text = "").

%   A path in the index is relative to the repository; the file is under
%   this process's root (lps_api.pl, lps_root/1).
absolute_of(Rel, File) :-
    lps_api:lps_root(Root),
    atomic_list_concat([Root, '/', Rel], File).

relative_of(File, Rel) :-
    lps_api:lps_root(Root),
    atom_concat(Root, '/', RootSlash),
    (   atom_concat(RootSlash, Rel, File) -> true
    ;   Rel = File
    ).

% ---------------------------------------------------------------------------
% The index

examples_index_size(N) :-
    index(index(N, _, _)).

%!  index_file(-File) is det.
%   Where the deployment's build writes the index, and where a search looks
%   for it: beside the examples.
index_file(File) :-
    absolute_of('examples/search-index.fast', File).

index(Index) :-
    example_files(Triples),
    stamp(Triples, Stamp),
    (   index_cache(Stamp, Index)
    ->  true
    ;   (   prebuilt_index(Stamp, Index0) -> Index = Index0
        ;   build_index(Triples, Index)
        ),
        retractall(index_cache(_, _)),
        assertz(index_cache(Stamp, Index))
    ).

%   The files the index describes (relative to the repository) with their
%   sizes: the same list where the index was written and where it is read
%   means the same programs.
stamp(Triples, Stamp) :-
    findall(Rel-S, ( member(_-_-Rel, Triples), absolute_of(Rel, F),
                     ( exists_file(F) -> size_file(F, S) ; S = 0 ) ), Stamp0),
    sort(Stamp0, Stamp).

prebuilt_index(Stamp, Index) :-
    index_file(File),
    exists_file(File),
    catch(setup_call_cleanup(open(File, read, In, [type(binary)]),
                             fast_read(In, Term),
                             close(In)),
          _, fail),
    Term = search_index(Stamp0, Index),
    Stamp0 == Stamp.

%!  write_index is det.
%!  write_index(+File, +Options) is det.
%
%   Build the index from the files and write it to File (write_index/0: to
%   index_file/1), as a fast term with its stamp. Options: only_list(ListFile)
%   — index only the files named in ListFile, one repository-relative path
%   per line: the browser build's payload list (wasm/build.sh), since that
%   build carries fewer examples than the server.
write_index :-
    index_file(File),
    write_index(File, []).
write_index(File, Options) :-
    example_files(Triples0),
    (   memberchk(only_list(ListFile), Options)
    ->  read_file_to_string(ListFile, S, []),
        split_string(S, "\n", " \t\r", Lines0),
        exclude(==(""), Lines0, Lines),
        findall(N-T-Rel, ( member(N-T-Rel, Triples0), atom_string(Rel, RS), memberchk(RS, Lines) ), Triples)
    ;   Triples = Triples0
    ),
    stamp(Triples, Stamp),
    build_index(Triples, Index),
    setup_call_cleanup(open(File, write, Out, [type(binary)]),
                       fast_write(Out, search_index(Stamp, Index)),
                       close(Out)),
    Index = index(N, _, _),
    print_message(informational, format("examples' search index: ~w programs written to ~w", [N, File])).

%   Every example the picker lists, with its title and its file, relative to
%   the repository: lps_api's own listing, read with every door open so that
%   the names are the ones the picker opens (listable/1 decides at search
%   time what a visitor sees).
example_files(Triples) :-
    findall(Name-Title-Rel,
            ( lps_api:example_list_all(Examples),
              member(E, Examples),
              get_dict(name, E, Name),
              ( get_dict(title, E, Title) -> true ; Title = "" ),
              lps_api:example_path(Name, File),
              exists_file(File),
              relative_of(File, Rel) ),
            Triples0),
    sort(Triples0, Triples).

build_index(Triples, index(N, DF, Entries)) :-
    findall(E, ( member(Name-Title-Rel, Triples), catch(entry(Name, Title, Rel, E), _, fail) ), Entries),
    length(Entries, N),
    findall(W, ( member(ex(_, _, _, FW, TW, XW, _), Entries),
                 ord_union([FW, TW, XW], Set), member(W, Set) ), Ws),
    msort(Ws, Sorted),
    clumped(Sorted, DF).

%   ex(Name, RelativeFile, Title, NameWords, DeclarationWords, TextWords,
%   DeclarationLines), the words as sets.
entry(Name, Title, Rel, ex(Name, Rel, Title, NameSet, TemplSet, TextSet, TLines)) :-
    absolute_of(Rel, File),
    read_file_to_string(File, Text, [encoding(utf8)]),
    name_words(Name, Title, NameWords), sort(NameWords, NameSet),
    file_name_extension(_, Ext, Rel),
    declaration_lines(Ext, Text, TLines),
    atomic_list_concat(TLines, ' ', TText),
    words(TText, TemplWords), sort(TemplWords, TemplSet),
    words(Text, TextWords), sort(TextWords, TextSet).

name_words(Name, Title, Words) :-
    format(string(S0), "~w", [Name]),
    re_replace("[_/\\-.]"/g, " ", S0, S1),
    format(string(S), "~w ~w", [S1, Title]),
    words(S, Words).

%!  declaration_lines(+Extension, +Text, -Lines) is det.
%
%   The declarations of a program. In an LPS program (`pl`, `lps`): the
%   `fluents`, `events` and `actions` declarations, each from its first
%   line to the full stop that ends it. In a Logical English document (`le`):
%   the declaration sections — the templates, the predicates, the ontology,
%   the fluents, the events, the actions, the constants, the functions — in
%   any of the dictionaries' languages, each up to the next section header.
%   Other files (PDDL, Inform 7, DRL): none.
declaration_lines(le, Text, Lines) :- !,
    split_string(Text, "\n", "\r", All),
    le_decl_lines(All, no, Lines).
declaration_lines(Ext, Text, Lines) :-
    memberchk(Ext, [pl, lps]), !,
    split_string(Text, "\n", "\r", All),
    lps_decl_lines(All, no, Lines).
declaration_lines(_, _, []).

lps_decl_lines([], _, []).
lps_decl_lines([L|Ls], In, Out) :-
    normalize_space(string(S), L),
    (   In == no, lps_decl_start(S)
    ->  Out = [S|Out1],
        ( sub_string(S, _, 1, 0, ".") -> In1 = no ; In1 = yes )
    ;   In == yes, S \== ""
    ->  Out = [S|Out1],
        ( sub_string(S, _, 1, 0, ".") -> In1 = no ; In1 = yes )
    ;   Out = Out1, In1 = In
    ),
    lps_decl_lines(Ls, In1, Out1).

lps_decl_start(S) :-
    member(K, ["fluents", "events", "actions"]),
    string_concat(K, Rest, S),
    ( Rest == "" ; sub_string(Rest, 0, 1, _, C), memberchk(C, [" ", "(", "\t"]) ), !.

le_decl_lines([], _, []).
le_decl_lines([L|Ls], In, Out) :-
    (   section_header(L)
    ->  ( declaration_header(L) -> In1 = yes ; In1 = no ),
        Out = Out1
    ;   In1 = In,
        ( In1 == yes, normalize_space(string(S), L), S \== "" -> Out = [S|Out1] ; Out = Out1 )
    ),
    le_decl_lines(Ls, In1, Out1).

section_header(L) :-
    normalize_space(string(S), L),
    sub_string(S, _, 1, 0, ":"),
    \+ sub_string(S, 0, 1, _, "%"),
    split_string(S, " ", "", Ws), length(Ws, N), N =< 12.

declaration_header(L) :-
    words(L, LW),
    declaration_phrase(P),
    sublist_(P, LW), !.

%   The headers' words in the five languages of LE2's dictionaries
%   (i18n/keywords.csv, the `section` rows), stemmed as words/2 stems them.
:- dynamic declaration_phrase_cache/1.
declaration_phrase(P) :-
    (   declaration_phrase_cache(_) -> true
    ;   forall(( declaration_header_text(T), words(T, Ws), Ws \== [] ),
               ( declaration_phrase_cache(Ws) -> true ; assertz(declaration_phrase_cache(Ws)) ))
    ),
    declaration_phrase_cache(P).

declaration_header_text(T) :-
    member(T, ["the templates are", "os modelos são", "las plantillas son", "les modèles sont", "i modelli sono",
               "the predicates are", "os predicados são", "los predicados son", "les prédicats sont", "i predicati sono",
               "the ontology is", "a ontologia é", "la ontología es", "la taxonomie est", "la tassonomia è",
               "the fluents are", "os fluentes são", "los fluentes son", "les fluents sont", "i fluenti sono",
               "the events are", "os eventos são", "los eventos son", "les événements sont", "gli eventi sono",
               "the actions are", "as ações são", "las acciones son", "les actions sont", "le azioni sono",
               "the constants are", "as constantes são", "las constantes son", "les constantes sont", "le costanti sono",
               "the functions are", "as funções são", "las funciones son", "les fonctions sont", "le funzioni sono"]).
