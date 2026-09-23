/* lps_to_le.pl — an LPS program in the older syntax, written as Logical English.
 *
 * The older syntax is the Prolog-like one: `fluents has(_, _).`, `praise(_,
 * Who) initiates sings(Who).`, `if ... then ... from T1 to T2.` — the syntax
 * of every `.lps` file in `examples/`. Logical English says the same things in
 * sentences (docs/user/reference/le-for-lps.md), and this module turns the
 * first into the second: one `.lps` file in, one `.le` document out, saying
 * the same thing and running the same way.
 *
 * ## How it works, and what it reuses
 *
 * Almost nothing here is new. The two halves already existed:
 *
 *   1. `lps_legacy_syntax:legacy_to_internal/4` reads the older syntax into
 *      the internal terms of the plan of record §I.3 — the same terms the
 *      engine runs, whichever syntax they were written in.
 *   2. LE2's `le_lps_write.pl` writes those internal terms back as Logical
 *      English. It was written for the round trip of §I.9.5 (English in,
 *      English out), and it needs a *template dictionary*: a template is
 *      what tells `played(miguel, rock)` from `beats(rock, scissors)`.
 *
 * A `.lps` file has no dictionary, because the older syntax has no templates.
 * So LE2 grew one predicate for this case, `le_lps_from_internal/4`, which
 * makes a dictionary up: it takes every predicate the program mentions, words
 * a template from the predicate's own name (`pick_up(Who, What)` becomes `*a
 * thing* picks up *a second thing*`), and binds the wording back to the name
 * with `; known as`. This module is the two halves joined, plus the reading of
 * the file and the reporting of whatever could not be carried over.
 *
 * The wording is a guess about English and carries no meaning: the `; known
 * as` binding does. That is why a converted program runs exactly as the
 * original did, which `tools/lps_to_le_test.pl` checks by running both and
 * comparing the traces.
 *
 * ## What needs saying out loud
 *
 *   - **Logical English is optional, and this needs it in this process.**
 *     `LPS_LE2_LIB` must name an LE2 checkout. With LE2 reached over HTTP or
 *     as a subprocess there is no way to hand it a list of Prolog terms, so
 *     the answer is a diagnostic saying which variable to set, never a guess.
 *   - **A directive is not carried over.** `:- lps_engine(planning, ...)` has
 *     no Logical English form; the document is written without it and the
 *     caller is told, because a converted program that had quietly stopped
 *     planning would be worse than one that refused.
 *   - **A companion is not a program.** Five `.lps` files under `examples/le/`
 *     are the companions of `.le` documents (drawing rules, Prolog helpers),
 *     not programs in their own right. Converting one alone is meaningless,
 *     and `companion_of/2` says so rather than producing half a document.
 */

:- module(lps_to_le, [
	lps_to_le_file/4,        % +File, +Options, -LEText, -Diags
	lps_to_le_text/5,        % +Text, +Name, +Options, -LEText, -Diags
	lps_to_le_terms/4,       % +Terms, +Options, -LEText, -Diags
	lps_to_le_ready/1,       % -Status   (ok | a message saying why not)
	companion_of/2,          % +LpsFile, -LEFile
	converted_from/2,        % +LEFile, -LpsName
	converted_from_text/2    % +LEText, -LpsName
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(option)).
:- use_module('../core/lps_diag').
:- use_module(lps_legacy_syntax).

%	Logical English lives behind an edge (`src/edges/lps_le.pl`), and an
%	edge is not something the syntax layer imports: it is reached the way
%	the core reaches this layer, by late binding, so that an image without
%	the edges still loads this file.
le_call(Goal) :-
	current_predicate(lps_le:lps_le_call/1),
	lps_le:lps_le_call(Goal).

%!	lps_to_le_ready(-Status) is det.
%
%	`ok` when Logical English can be reached in this process, otherwise a
%	message naming the environment variable to set.
lps_to_le_ready(Status) :-
	(   \+ current_predicate(lps_le:lps_le_available/1)
	->  Status = 'this image has no Logical English edge (src/edges/lps_le.pl)'
	;   lps_le:lps_le_available(lib(_))
	->  Status = ok
	;   Status = 'converting to Logical English needs LE2 loaded into this \c
		      process: set LPS_LE2_LIB to an LE2 checkout (LPS_LE2_URL \c
		      and LPS_LE2_DIR cannot be handed a program\'s terms)'
	).

%!	lps_to_le_file(+File, +Options, -LEText, -Diags) is det.
%
%	Read the `.lps` program File and write it as a Logical English
%	document. Options are those of lps_to_le_terms/4; the knowledge base is
%	named after the file and the document says which file it came from,
%	unless the caller says otherwise.
lps_to_le_file(File, Options, LEText, Diags) :-
	file_base_name(File, Base),
	file_name_extension(Name, _, Base),
	default_options(Base, Name, Options, Options1),
	(   companion_of(File, LE)
	->  LEText = "",
	    file_base_name(LE, LEBase),
	    format(atom(M),
		   'this file is the companion of the Logical English document \c
		    ~w, not a program of its own: convert nothing, and read ~w',
		   [LEBase, LEBase]),
	    diag(error, companion_file, src(File, 0, 0, legacy), M, D),
	    Diags = [D]
	;   legacy_to_internal(file(File), [], Ts, ReadDiags),
	    (	read_ok(ReadDiags)
	    ->	findall(T, member(t(T, _), Ts), Terms),
		lps_to_le_terms(Terms, Options1, LEText, ConvDiags),
		append(ReadDiags, ConvDiags, Diags)
	    ;	LEText = "", Diags = ReadDiags
	    )
	).

read_ok(Diags) :- \+ ( member(D, Diags), D = diag(error, _, _, _, _) ).

default_options(Base, Name, Options, Options1) :-
	(   memberchk(kb(_), Options) -> O1 = Options ; O1 = [kb(Name)|Options] ),
	(   memberchk(comment(_), O1)
	->  Options1 = O1
	;   marker_prefix(Marker),
	    format(string(C),
		   "~w~w\nThis document was written from the LPS program ~w, \c
		    which says the same thing in the older syntax. The two run \c
		    alike, and tools/lps_to_le_test.pl checks that they do. The \c
		    first line above is what keeps the older file from being \c
		    read as this document's companion, which would run every \c
		    rule twice.",
		   [Marker, Base, Base]),
	    Options1 = [comment(C)|O1]
	).

%!	marker_prefix(-Prefix) is det.
%
%	The words that open a converted document's first comment line,
%	followed by the name of the program it was written from:
%
%	    % lps-converted-from: fox_crow.lps
%
%	A `.le` document is otherwise compiled together with any `.lps` file
%	of the same name beside it (docs/user/reference/le-for-lps.md §7), and
%	a converted document's original IS that file -- so the pair would run
%	every rule twice. The marker is how the two are told apart, and it is
%	a comment, so it costs the document nothing.
marker_prefix('lps-converted-from: ').

%!	converted_from(+LEFile, -LpsName) is semidet.
%
%	LEFile is a converted document and LpsName is the `.lps` file it was
%	written from. False for a document somebody wrote by hand.
converted_from(LEFile, LpsName) :-
	catch(read_file_head(LEFile, Head), _, fail),
	converted_from_text(Head, LpsName).

read_file_head(File, Head) :-
	setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
			   read_string(In, 400, Head),
			   close(In)).

%!	converted_from_text(+LEText, -LpsName) is semidet.
%
%	The same for a document held as text, which is what an editor has.
converted_from_text(LEText, LpsName) :-
	sub_string(LEText, Before, _, _, "lps-converted-from:"),
	Before < 300,
	sub_string(LEText, Before, _, 0, Rest0),
	split_string(Rest0, "\n", "", [Line|_]),
	split_string(Line, ":", " \t", [_, Name0|_]),
	split_string(Name0, " \t", " \t", [Name|_]),
	Name \== "",
	atom_string(LpsName, Name).

%!	lps_to_le_text(+Text, +Name, +Options, -LEText, -Diags) is det.
%
%	The same for a program held as text, which is what an editor has.
lps_to_le_text(Text, Name, Options, LEText, Diags) :-
	file_base_name(Name, Base),
	(   file_name_extension(Stem, _, Base) -> true ; Stem = Base ),
	default_options(Base, Stem, Options, Options1),
	(   current_predicate(lps_source:lps_read_terms_string/4)
	->  lps_source:lps_read_terms_string(Text, Name, Raw, ReadDiags)
	;   Raw = [], ReadDiags = []
	),
	(   read_ok(ReadDiags)
	->  legacy_to_internal(terms(Raw), [origin(Name)], Ts, TDiags),
	    (	read_ok(TDiags)
	    ->	findall(T, member(t(T, _), Ts), Terms),
		lps_to_le_terms(Terms, Options1, LEText, ConvDiags),
		append([ReadDiags, TDiags, ConvDiags], Diags)
	    ;	LEText = "", append(ReadDiags, TDiags, Diags)
	    )
	;   LEText = "", Diags = ReadDiags
	).

%!	lps_to_le_terms(+Terms, +Options, -LEText, -Diags) is det.
%
%	The internal terms of a program, as a Logical English document.
%	Options: kb(Name) names the knowledge base, comment(Text) is written
%	above the document as a comment block.
lps_to_le_terms(Terms, Options, LEText, Diags) :-
	lps_to_le_ready(Status),
	(   Status \== ok
	->  LEText = "",
	    diag(error, le_not_loaded, unknown, Status, D),
	    Diags = [D]
	;   le_call(le_service:le_lps_from_internal(Terms, Options, Text, Issues))
	->  LEText = Text,
	    maplist(issue_diag, Issues, Diags)
	;   LEText = "",
	    diag(error, conversion_failed, unknown,
		 'Logical English could not write this program; \c
		  its terms are there but the writer refused them', D),
	    Diags = [D]
	).

issue_diag(issue(Severity, Code, Message), D) :-
	( memberchk(Severity, [error, warning, info]) -> S = Severity ; S = warning ),
	diag(S, Code, unknown, Message, D).

%!	companion_of(+LpsFile, -LEFile) is semidet.
%
%	LpsFile is the companion of the Logical English document LEFile: the
%	two have the same name, and the engine reads them together
%	(docs/user/reference/le-for-lps.md §7). Such a file holds the part of a
%	program that Logical English does not say — drawing rules, Prolog
%	helpers — and means nothing on its own.
companion_of(LpsFile, LEFile) :-
	atom_string(A, LpsFile),
	atom_concat(Base, '.lps', A),
	atom_concat(Base, '.le', LEFile),
	exists_file(LEFile),
	%  ... unless that document was written FROM this file, in which case
	%  the two are the same program and neither is half of anything.
	\+ ( converted_from(LEFile, Name),
	     file_base_name(A, LpsBase),
	     ( Name == LpsBase -> true ; file_name_extension(N, _, LpsBase), Name == N ) ).
