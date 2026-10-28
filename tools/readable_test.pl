/*  readable_test.pl — File > Save as a readable document, and /readable/.

    The document of a program for people who do not use the IDE is LE2's
    le_readable.pl; what is LPS2's is checked here: the operation makes it
    from a tab's text or from an example of this server, converts an .lps
    program first, and links a sentence of an included base to that base's
    own document on this server's /readable/ route, at the definition.
    The route's gate (signed-in visitors only) needs a running server with
    lpsPlus's sign-in: docs/dev/le-lps-interface.md says how it was tried.

    LPS_LE2_LIB=/path/to/LogicalEnglish2 \
      ./myswipl.sh -q -g run_tests -t halt tools/readable_test.pl
*/
:- use_module(library(plunit)).
:- use_module('../src/edges/lps_api').

doc(Dict, R) :- lps_api:operation("readable_document", Dict, R).

:- begin_tests(readable).

test(from_an_example) :-
    doc(_{example: "le/goat", format: "md"}, R),
    assertion(R.ok == true),
    assertion(R.fileName == "goat.md"),
    assertion(sub_string(R.content, 0, _, _, "# goat")).

test(from_a_tab) :-
    read_file_to_string('examples/le/goat.le', S, []),
    doc(_{source: S, name: "goat.le", format: "html", style: "legal"}, R),
    assertion(sub_string(R.content, _, _, _, "style-legal")).

test(an_lps_program_is_converted_first) :-
    doc(_{example: "le/life", format: "md"}, R0),
    assertion(R0.ok == true),
    read_file_to_string('examples/le/life.lps', S, []),
    doc(_{source: S, name: "life.lps", format: "md"}, R),
    assertion(R.ok == true),
    assertion(R.fileName == "life.md").

test(a_base_links_to_its_own_document_at_the_definition) :-
    doc(_{example: "le/fee_token", format: "md", linkBase: "https://lps2.example"}, R),
    assertion(sub_string(R.content, _, _, _, "(https://lps2.example/readable/le/token?format=html#p-transfers_to-3)")),
    doc(_{example: "le/token", format: "md"}, T),
    assertion(sub_string(T.content, _, _, _, "<a id=\"p-transfers_to-3\"></a>")).

test(no_such_example) :-
    doc(_{example: "le/nonesuch"}, R),
    assertion(R.ok \== true),
    assertion(get_dict(not_found, R, true)).

test(word_document) :-
    doc(_{example: "le/goat", format: "docx"}, R),
    assertion(R.encoding == "base64"),
    assertion(R.fileName == "goat.docx").

:- end_tests(readable).
