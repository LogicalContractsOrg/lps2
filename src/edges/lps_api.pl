/* lps_api.pl — the operations, with the transport taken out.
 *
 * Every request the IDE makes is a JSON object with an `operation` field, and
 * every reply is a JSON object. `operation/3` is that mapping: forty-odd
 * operations, from `compile` to `automaton`, and the registry of programs and
 * sessions they hand out handles to.
 *
 * It was lps_http.pl until there were two ways in. lps_http.pl is still the
 * one that matters on a server — it reads the POST, checks the token, calls
 * handle/2 and writes the reply — but it is no longer the only one: the
 * WebAssembly build (wasm/lps_wasm_app.pl) compiles this file into a page and
 * calls the same handle/2 from a worker, with no server anywhere. An
 * operation is implemented once and the two deployments cannot drift.
 *
 * The line between the two files is what a transport owes this one:
 *
 *   - lps_http.pl keeps the HTTP server, the routes, the landing page, the
 *     IDE and documentation handlers, the asset server, token authorisation,
 *     CORS, and the MCP endpoint's envelope;
 *   - this file keeps everything that turns a request dict into a reply dict,
 *     including the compile/session registries, the front-end converters
 *     (PDDL, DRL, Inform, Logical English) and the example tree.
 *
 * It is an *edge*, and may use threads and files as the edges do — but it
 * should reach for a thread only where nothing else will do: the browser
 * build has exactly one, and a file system of its own holding whatever the
 * payload put in it (wasm/pack.pl).
 */

:- module(lps_api, [
	handle/2,                % +RequestDict, -ReplyDict
	operation/3,             % +Op, +RequestDict, -ReplyDict
	example_list/1,          % -Dict          (the landing page's tree, too)
	example_dir/2,           % -Dir, -Label
	lps_root/1               % -Dir
	]).

:- use_module(library(filesex)).
:- use_module(library(time)).
:- use_module(library(json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(yall)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../syntax/lps_internal_syntax').
:- use_module('../core/lps_explain').
:- use_module(lps_source).
:- use_module(lps_le).
:- use_module(lps_sandbox).
:- use_module(lps_assistant).
:- use_module(lps_live).
:- use_module(lps_play).
:- use_module('../syntax/lps_inform').
:- use_module(lps_wasm).
:- use_module(lps_models).
:- use_module(lps_ids).
:- use_module('../syntax/lps_pddl').
:- use_module('../syntax/lps_to_le').
:- use_module('../syntax/lps_plus').
:- use_module('../syntax/lps_surface_write').
:- use_module(lps_telemetry).

:- dynamic registered_program/2.   % Id, Program
:- dynamic registered_session/3.   % Id, Session, LastUsed

:- dynamic session_counter_http/1.

session_counter_http(0).

		 /*******************************
		 *     converting front ends	*
		 *******************************/

%	Files is a list of f(Name, Content): Content the file's text (a string),
%	or base64(B) for a binary file (a zipped source tree), which only the
%	Logical English installation's translators read.
convert_inputs(Dict, Files) :-
	(   get_dict(files, Dict, Fs), is_list(Fs)
	->  findall(f(N, C), ( member(F, Fs), get_dict(name, F, N), input_content(F, C) ), Files)
	;   get_dict(name, Dict, N), input_content(Dict, C)
	->  Files = [f(N, C)]
	;   Files = []
	).

input_content(D, base64(B)) :- get_dict(base64, D, B), !.
input_content(D, S) :- get_dict(source, D, S).

%!	convert_groups(+Files, -Groups) is det.
%
%	The files opened at once, as the programs they make, the way the example
%	picker and the command line pair them: a PDDL problem with the domain it
%	names (`(:domain blocks-domain)`), a `.drl` with the `.wording` of its
%	name. Every other file is a program of its own; a domain no problem
%	names, a problem without its domain, a wording without its rule file are
%	groups of their own too, so the reply says what is missing.
convert_groups(Files, Groups) :-
	partition([f(N, S)]>>( is_pddl(f(N, S)), string(S) ), Files, Pddl, Rest0),
	partition(is_pddl_problem, Pddl, Problems, Domains),
	findall(G, pddl_group(Problems, Domains, G), PGs),
	findall([D], ( member(D, Domains), \+ ( member(G, PGs), memberchk(D, G) ) ), DGs),
	partition([f(N, _)]>>sub_atom_ci(N, '.wording'), Rest0, Wordings, Rest),
	findall(G, ( member(F, Rest), drl_group(F, Wordings, G) ), RGs),
	findall([W], ( member(W, Wordings), W = f(WN, _), wording_stem(WN, St),
		       \+ ( member(f(DN, _), Rest), sub_atom_ci(DN, '.drl'), wording_stem(DN, St) ) ), WGs),
	append([PGs, DGs, RGs, WGs], Groups).

pddl_group(Problems, Domains, Group) :-
	member(P, Problems), P = f(_, PS),
	(   pddl_declared_domain(PS, Name), member(D, Domains), D = f(_, DS), pddl_defines_domain(DS, Name)
	->  Group = [D, P]
	;   Domains = [D], Problems = [_]	% one of each: they belong together
	->  Group = [D, P]
	;   Group = [P]
	).

drl_group(F, Wordings, Group) :-
	F = f(N, _),
	(   sub_atom_ci(N, '.drl'), wording_stem(N, St),
	    member(W, Wordings), W = f(WN, _), wording_stem(WN, St)
	->  Group = [F, W]
	;   Group = [F]
	).

wording_stem(Name, Stem) :-
	atom_string(A, Name), file_base_name(A, B),
	file_name_extension(S0, _, B), downcase_atom(S0, Stem).

%!	convert_group_reply(+Files, -Reply) is det.
%
%	One program of convert_groups/2, as the IDE opens it: its name and text,
%	the notes, what it came from (`origin`) and that source, verbatim.
convert_group_reply(Files, Reply) :-
	findall(N, member(f(N, _), Files), Ns0), maplist([N0, N1]>>format(string(N1), '~w', [N0]), Ns0, Ns),
	atomic_list_concat(Ns, ' + ', Origin0), atom_string(Origin0, Origin),
	(   Files = [f(_, S)], string(S)
	->  Original = S
	;   findall(Part, ( member(f(FN, FS), Files),
			    (   string(FS) -> format(string(Part), '% ==== ~w ====\n~w', [FN, FS])
			    ;   format(string(Part), '% ==== ~w ==== (a binary file)', [FN]) ) ), Parts),
	    atomic_list_concat(Parts, '\n', Original0), atom_string(Original0, Original)
	),
	Files = [f(N1, _)|_],
	catch(( convert_files(Files, Name, Source, Diags) -> Outcome = ok ; Outcome = none ),
	      E, Outcome = error(E)),
	(   Outcome == ok
	->  maplist(diag_dict, Diags, DD),
	    Reply = _{ok: true, name: Name, source: Source, diagnostics: DD,
		      origin: Origin, original: Original}
	;   Outcome == none
	->  format(string(M), 'nothing here converts ~w: expected a PDDL domain and its problem, a .drl (with its .wording), an Inform 7 story (.ni), or a file a translator of the Logical English installation reads', [Origin]),
	    Reply = _{ok: false, name: N1, origin: Origin, error: M}
	;   Outcome = error(E1),
	    convert_error_text(E1, M),
	    Reply = _{ok: false, name: N1, origin: Origin, error: M}
	).

convert_error_text(error(format(M), _), M) :- !.
convert_error_text(E, M) :-
	(   catch(message_to_codes(E, _, Cs), _, fail) -> format(string(M), 'could not convert: ~s', [Cs])
	;   format(string(M), 'could not convert: ~q', [E])
	).

/*  PDDL first, because it is the one that needs two files. A `.pddl` naming
    itself `(define (problem …))` is the problem; `(define (domain …))` is the
    domain. Given only one of them we say which is missing rather than
    producing half a program — a problem without its domain has no actions, and
    a domain without its problem has no goal. */
convert_files(Files, Name, Source, Diags) :-
	include(is_pddl, Files, Pddl), Pddl \== [], forall(member(f(_, S), Pddl), string(S)), !,
	partition(is_pddl_problem, Pddl, Problems, Domains),
	(   Domains = [f(DN, DS)|_], Problems = [f(PN, PS)|_]
	->  with_temp_file(DS, '.pddl', DF,
	      with_temp_file(PS, '.pddl', PF,
		pddl_to_internal(DF, PF, Terms, Diags))),
	    format(atom(Origin), '~w + ~w', [DN, PN]),
	    convert_name(PN, Name)
	;   Domains = [f(DN, _)|_]
	->  Terms = [], Origin = DN, convert_name(DN, Name),
	    Diags = [diag(error, pddl_no_problem, src(DN, 1, 0, pddl),
			  'a PDDL domain has no goal on its own: open the domain and its problem file together (File \u25b8 Open takes several at once)', [])]
	;   Problems = [f(PN, _)|_],
	    Terms = [], Origin = PN, convert_name(PN, Name),
	    Diags = [diag(error, pddl_no_domain, src(PN, 1, 0, pddl),
			  'a PDDL problem has no actions on its own: open the problem and its domain file together (File \u25b8 Open takes several at once)', [])]
	),
	%  The same trailer `./lps pddl` adds: a PDDL problem is a planning
	%  problem, and `achieve` without `lps_engine(planning, …)` is a
	%  compile error rather than a program. A buffer has to be runnable as
	%  it stands.
	Trailer = [ (:- lps_engine(planning, [search(auto), horizon(20), max_concurrency(1)])),
		    maxTime(24) ],
	append(Terms, Trailer, Terms1),
	render_converted(Terms1, Origin, pddl, Diags, Source).
convert_files(Files, Name, Source, Diags) :-
	member(f(N, S), Files), sub_atom_ci(N, '.drl'),
	\+ lps_plus_available(drools), !,
	%  The DRL front end lives in lpsPlus (../syntax/lps_plus.pl): with no
	%  checkout here the file opens as itself, with the reason in a
	%  diagnostic, exactly as a `.sol` does below.
	Source = S, atom_string(N, Name),
	lps_plus_message(drools, M),
	Diags = [diag(error, no_drools_translator, src(N, 1, 0, drl), M, [])].
convert_files(Files, Name, Source, Diags) :-
	member(f(N, S), Files), sub_atom_ci(N, '.drl'), !,
	%  The rule base's wording table (lps_drools: the words and names of
	%  its fluents and events), when it comes with it.
	(   member(f(WN, WS), Files), sub_atom_ci(WN, '.wording')
	->  DOpts = [wording_text(WS)]
	;   DOpts = []
	),
	with_temp_file(S, '.drl', F,
		       ( lps_drools:drl_reading(F, DOpts, reading(Terms0, Diags, World)),
			 lps_drools:drl_initially_example(World, Terms0, Initially) )),
	%  A rule base with no facts does nothing; the CLI takes `--facts`, and
	%  in a buffer the author writes an `initially` line. The empty
	%  `initial_state([])` this used to carry has no surface form — `initially`
	%  with nothing after it is not a sentence — so the prompt is a comment in
	%  the header instead.
	append(Terms0, [maxTime(8)], Terms),
	convert_name(N, Name),
	render_converted(Terms, N, drools(Initially), Diags, Source).

/*  An Inform 7 story opens as the Logical English story its assertions make,
    as it does from the example picker (example_converted/5) and in `lps
    inform`. What was not translated (the rule register) is listed at the top
    of the document, where the IDE's status line says the notes are. */
convert_files(Files, Name, Source, Diags) :-
	member(f(N, S), Files), string(S),
	( sub_atom_ci(N, '.ni') ; sub_atom_ci(N, '.inform') ), !,
	atom_string(NA, N), file_base_name(NA, Base),
	tmp_file(inform, Dir),
	setup_call_cleanup(
	    make_directory(Dir),
	    ( atomic_list_concat([Dir, '/', Base], Path),
	      setup_call_cleanup(open(Path, write, Out, [encoding(utf8)]), write(Out, S), close(Out)),
	      inform_converted(Path, Base, Name, Source, Diags) ),
	    catch(delete_directory_and_contents(Dir), _, true)).
%	A `.wording` file is the words of a rule base: opened without its `.drl`
%	there is nothing to convert, and the reply says so.
convert_files([f(N, _)], _Name, _Source, _Diags) :-
	sub_atom_ci(N, '.wording'), !,
	format(string(M), '~w is the wording of a Drools rule file: open it together with its .drl (File \u25b8 Open takes several at once)', [N]),
	throw(error(format(M), _)).

/*  Another system's file — a Solidity contract, a Miniscript policy, a Daml
    or LegalRuleML file, whatever the Logical English installation has a
    translator for — is opened as Logical English: LE2's import registry
    (le_import.pl) hands it to that translator (the InsurLE extensions keep
    them, not here), and what comes back is a `.le` document, which the IDE
    then treats like any other LE document. The extensions come from the
    registry itself (le_foreign_extension/1), so a new translator needs no
    change here. Without LE2 in this process, or without the translator, the
    reply says so and the file opens as it is. PDDL and Drools, which LPS2
    reads itself, are handled above. */
convert_files(Files, Name, Source, Diags) :-
	member(f(N, S), Files),
	atom_string(NA, N), file_name_extension(_, Ext0, NA), downcase_atom(Ext0, Ext),
	Ext \== le, le_foreign_extension(Ext), !,
	lps_root(Root),
	atomic_list_concat([Root, '/build/imports'], ImportRoot),
	( S = base64(B) -> Content = base64(B) ; Content = text(S) ),
	(   lps_le_call(( load_files(le2(le_import), [if(not_loaded), silent(true)]),
			  le_import:import_upload(N, Content, Reply, [root(ImportRoot)]) ))
	->  (   get_dict(document, Reply, Source0)
	    ->  get_dict(fileName, Reply, Name0), atom_string(Name0, Name),
		(   get_dict(notes, Reply, Notes) -> true ; Notes = [] ),
		findall(diag(warning, foreign_import, unknown, Note, []),
			member(Note, Notes), Diags),
		%  the notes where the IDE says they are: at the top of the document
		notes_comment(N, Diags, NotesText),
		string_concat(NotesText, Source0, Source)
	    ;   ( get_dict(error, Reply, Why) -> true ; Why = 'the translator gave no document' ),
		format(string(M), 'could not open ~w: ~w', [N, Why]),
		throw(error(format(M), _))
	    )
	;   string(S)
	->  Source = S, atom_string(N, Name),
	    Diags = [diag(error, no_translator, src(N, 1, 0, Ext),
			  'no translator here: Logical English (LPS_LE2_LIB) with the InsurLE extensions is needed to open this file as Logical English', [])]
	;   format(string(M), 'no translator here for ~w: Logical English (LPS_LE2_LIB) with the InsurLE extensions is needed to open it', [N]),
	    throw(error(format(M), _))
	).
convert_files(Files, Name, Source, Diags) :-
	member(f(N, S), Files), sub_atom_ci(N, '.sol'), !,
	Source = S, atom_string(N, Name),
	Diags = [diag(error, no_solidity_translator, src(N, 1, 0, solidity),
		      'no Solidity translator here: Logical English (LPS_LE2_LIB) with the InsurLE extensions is needed to open a contract as LE for LPS', [])].

%!	inform_converted(+Path, +Base, -Name, -Text, -Diags) is det.
%
%	The story at Path (whose file is called Base) as Logical English, with
%	what did not carry over as comments at the top, each with its line.
inform_converted(Path, Base, Name, Text, Diags) :-
	lps_inform:inform_to_le(Path, Text0, _Companion, Diags0),
	maplist(diag_in_file(Base), Diags0, Diags),
	file_name_extension(Stem, _, Base),
	lps_inform:story_name(Stem, Story),
	atom_concat(Story, '.le', Name0), atom_string(Name0, Name),
	notes_comment(Base, Diags, Notes),
	string_concat(Notes, Text0, Text).

diag_in_file(Base, diag(S, C, src(_, L, Col, K), M, F), diag(S, C, src(Base, L, Col, K), M, F)) :- !.
diag_in_file(_, D, D).

%	The notes of a conversion whose document does not carry them itself, as
%	a comment block to put above it ('' when there are none).
notes_comment(_, [], "") :- !.
notes_comment(Origin, Diags, Text) :-
	length(Diags, N),
	findall(L, ( member(diag(Sev, _, Pos, Msg, _), Diags),
		     (   Pos = src(_, Line, _, _), integer(Line), Line > 0
		     ->  format(string(L), '%   ~w (line ~w): ~w', [Sev, Line, Msg])
		     ;   format(string(L), '%   ~w: ~w', [Sev, Msg])
		     ) ), Ls),
	atomic_list_concat(Ls, '\n', Body),
	format(string(Text), '% Converted from ~w on opening, with ~w note(s) (what did not carry over, and what is worth knowing):\n~w\n%\n\n',
	       [Origin, N, Body]).

%	An extension a translator of the LE installation reads (none without
%	LE2 in this process).
le_foreign_extension(Ext) :-
	\+ memberchk(Ext, [pl, lps, lpsw, 'P', p, le, pddl, drl, wording, ni, inform, txt]),	% LPS2's own
	lps_le_call(le_service:le_import_formats(Fs)),
	member(F, Fs), get_dict(extensions, F, Es),
	member(E0, Es), atom_string(E, E0), E == Ext, !.

is_pddl(f(N, _)) :- sub_atom_ci(N, '.pddl').

%	The formats LPS2 converts itself on opening (the Logical English
%	installation's come from le_service:le_import_formats/1): File ▸ Open
%	offers their extensions and its tooltip names them.
lps2_import_format(_{id: "pddl", title: "a PDDL planning domain with its problem", extensions: ["pddl"]}).
%	The Drools reader is lpsPlus's (../syntax/lps_plus.pl), so it is only
%	offered where there is one: without it File ▸ Open neither lists a
%	`.drl` nor accepts one.
lps2_import_format(_{id: "drools", title: "a Drools rule file, with its wording file", extensions: ["drl", "wording"]}) :-
	lps_plus_available(drools).
lps2_import_format(_{id: "inform", title: "an Inform 7 story", extensions: ["ni"]}).

%	A problem says `(define (problem …`; a domain says `(define (domain …`.
is_pddl_problem(f(_, S)) :-
	string_lower(S, L),
	sub_string(L, B, _, _, "define"),
	sub_string(L, B2, _, _, "problem"),
	B2 > B, B2 - B < 40, !.

sub_atom_ci(A, Suffix) :-
	atom_string(A, S), string_lower(S, L), string_lower(Suffix, LS),
	sub_string(L, _, _, 0, LS).

convert_name(In, Out) :-
	atom_string(A, In),
	file_base_name(A, Base),
	( file_name_extension(Stem, _, Base) -> true ; Stem = Base ),
	%  `.lps`, not `.lpsw`: the buffer is surface syntax now, and `.lpsw` is
	%  what both the CLI (lps_cli.pl:syntax_of/3) and the IDE's tab
	%  (ui/src/tabs.js) read as *internal*. Getting this wrong would hand the
	%  compiler a surface program and tell it to expect the other one.
	atomic_list_concat([Stem, '.lps'], Out0),
	atom_string(Out0, Out).

/*	A converted program says where it came from. Not decoration: the buffer
	is generated, and six months later the only question about it is "what
	was this before?".

	The body is *surface* LPS, not the internal representation the front end
	produces. A student opening a PDDL domain should meet the language the
	tutorial teaches — `pick_up(X) terminates ontable(X)` — and not
	`terminated(happens(pick_up(A),B,C), ontable(A), [])`. The writer checks
	itself (it re-reads what it wrote), and if the check fails we keep the
	internal rendering and say so: a buffer that no longer means what the
	converter said would be worse than an ugly one. */
render_converted(Terms, Origin, Kind, Diags, Source) :-
	get_time(Now),
	format_time(atom(When), '%Y-%m-%d %H:%M', Now),
	origin_note(Kind, Note),
	surface_body(Terms, Body, ExtraDiags),
	append(Diags, ExtraDiags, AllDiags),
	(   AllDiags == []
	->  DiagText = ''
	;   findall(L, ( member(D, AllDiags), diag_comment(D, L) ), Ls),
	    atomic_list_concat(Ls, '\n', DiagText0),
	    format(atom(DiagText), '%\n% What did not carry over:\n~w\n', [DiagText0])
	),
	format(string(Source),
	       '% Converted from ~w by LPS2 on ~w.\n%\n~w~w\n~w',
	       [Origin, When, Note, DiagText, Body]).

surface_body(Terms, Body, []) :-
	internal_to_surface(Terms, Body, []), !.
surface_body(Terms, Body, [D]) :-
	with_output_to(string(Internal), write_internal_terms(Terms)),
	format(string(Body),
	       '%  NOTE: this is LPS internal syntax. The surface rendering of\n\c
		%  this program did not read back as the same program, so the\n\c
		%  form the compiler consumes is shown instead.\n~w', [Internal]),
	diag(warning, surface_fallback, unknown,
	     'shown in internal syntax: the surface rendering did not round-trip', D).

%	The front ends emit `t(Term, Provenance)` pairs — the LE interface shape
%	(docs/dev/le-lps-interface.md §1) — so the compiler can point a diagnostic at
%	the .pddl line it came from. For a *buffer* we want the terms.
write_internal_terms(Terms) :-
	forall(member(T0, Terms),
	       ( ( T0 = t(T, _) -> true ; T = T0 ),
		 \+ var(T),
		 %  Named variables, not `_24398`: this text goes into an editor
		 %  and somebody is going to read and change it.
		 \+ \+ ( numbervars(T, 0, _),
			 format('~W.~n', [T, [quoted(true), numbervars(true)]]) ) )).

origin_note(pddl, '% PDDL: preconditions became denials, effects became causal laws, and the\n% problem\'s :goal became `achieve`. The planner is the one every other LPS\n% program uses.\n').
origin_note(drools(Initially), Note) :-
	Note0 = '% Drools DRL: `when`/`then` became reactive rules. The facts are states of\n% the world (a boolean field a state of its own: `sprinkler_on(Room)`), and\n% what a rule does to working memory is an event in it: an insert something\n% starting, a delete it ending, a modify it changing (`sprinkler_turns_on`),\n% each with its causal law. A rule that only inserts waits until what it\n% inserted is gone, as Drools fires a rule once. Words and names come from a\n% `<name>.wording` file beside the DRL, if there is one. Salience, rule attributes\n% (no-loop, agenda-group…) and Java leaves are reported below rather than\n% guessed at.\n%\n% A rule base needs facts to work on. Add them as an `initially` line',
	(   Initially == ''
	->  atom_concat(Note0, '.\n', Note)
	;   format(atom(Note), '~w, in this shape:\n%   ~w\n', [Note0, Initially])
	).

diag_comment(diag(Sev, _, _, Msg, _), Line) :-
	format(atom(Line), '%   ~w: ~w', [Sev, Msg]).

with_temp_file(Text, Ext, File, Goal) :-
	tmp_file_stream(text, Base, Out0),
	close(Out0),
	atom_concat(Base, Ext, File),
	setup_call_cleanup(
	    ( open(File, write, S, [encoding(utf8)]), write(S, Text), close(S) ),
	    Goal,
	    ( catch(delete_file(File), _, true), catch(delete_file(Base), _, true) )).

/*  Why the run stopped, in words. "success after 21 cycles" answers how far it
    got and not why it stopped there, and those are different questions: a run
    that hit `maxTime` and a run that ran out of things to do both say
    "success", and only one of them is finished. */
stop_phrase(S, Status, Phrase) :-
	lps_session_program(S, P),
	lps_session_time(S, Time),
	(   Status = terminated(Cause)
	->  format(string(Phrase), 'the program terminated (~w)', [Cause])
	;   Status == failure
	->  Phrase = "a cycle could not be completed"
	;   Status = error(E)
	->  format(string(Phrase), 'the engine raised ~w', [E])
	;   prog_setting(P, maxTime, MT), number(MT), Time > MT
	->  format(string(Phrase), 'reached maxTime(~w)', [MT])
	;   Phrase = "nothing left to do"
	).

%!	example_source(+Name, -Text) is semidet.
%
%	Names may be paths under the corpus (`CLOUT_workshop/badlight`), which is
%	what list_examples returns, or bare names, which is what the older API
%	took and what a `?example=` link still carries.
example_source(Name, Text) :-
	example_source(Name, _, Text).

%!	example_source(+Name, -FileName, -Text) is semidet.
%
%	FileName is the file as found — with its extension, which the name
%	asked for may lack (`?example=if/doors` opens `doors.le`). The editor
%	names the tab after it, and the extension is what tells the editor
%	the syntax: a story opened as `doors` was read as LPS, would not
%	compile, and could not be played.
example_source(Name, FileName, Text) :-
	example_path(Name, Path),
	exists_file(Path),
	file_base_name(Path, Base), atom_string(Base, FileName),
	read_file_to_string(Path, Text, [encoding(utf8)]).

%!	example_originals(+Name, -Origin, -Text) is semidet.
%
%	What an example was converted from, when it keeps its originals the
%	way LE2's migrations do: in a `sources/` folder beside it (a Solidity
%	twin's contract, say). View > The original this was converted from
%	shows them; several files come one after another under their names.
example_originals(Name, Origin, Text) :-
	example_path(Name, Path),
	file_directory_name(Path, Dir),
	atomic_list_concat([Dir, '/sources'], SDir),
	exists_directory(SDir),
	findall(Rel-F, ( directory_member(SDir, F, [recursive(true)]), exists_file(F),
			 file_name_extension(_, Ext0, F), downcase_atom(Ext0, Ext),
			 \+ memberchk(Ext, [pdf, png, jpg, jpeg, gif, zip, docx, xlsx, doc, xls]),
			 atom_concat(SDir, '/', P), atom_concat(P, R, F),
			 atom_concat('sources/', R, Rel) ), Pairs0),
	msort(Pairs0, Pairs),
	Pairs \== [],
	(   Pairs = [Rel-F]
	->  Origin = Rel, read_file_to_string(F, Text, [encoding(utf8)])
	;   length(Pairs, N), format(string(Origin), 'sources/ (~w files)', [N]),
	    findall(Part, ( member(R-F, Pairs), size_file(F, Sz), Sz < 200000,
			    read_file_to_string(F, T, [encoding(utf8)]),
			    format(string(Part), '=== ~w ===~n~w', [R, T]) ), Parts),
	    atomic_list_concat(Parts, '\n', Text0), atom_string(Text0, Text)
	).

%!	example_companion(+Name, -CompanionName, -Text) is semidet.
%
%	A Logical English example arrives with its `.lps` companion, for exactly
%	the reason a PDDL problem arrives with its domain: `badlight.le` and
%	`badlight.lps` are one program (docs/user/reference/le-for-lps.md §7), and a picker
%	that hands over half of it has asked the reader to go and find the rest.
%	The companions are deliberately not *listed* — they are not Logical
%	English documents and a list of them under that heading would say they
%	were — so this is the only way they reach the editor.
example_companion(Name, CName, Text) :-
	example_path(Name, Path),
	exists_file(Path),
	file_name_extension(Base, le, Path),
	file_name_extension(Base, lps, CPath),
	exists_file(CPath),
	file_base_name(CPath, CName0), atom_string(CName0, CName),
	read_file_to_string(CPath, Text, [encoding(utf8)]).

/*  A PDDL or Drools example arrives converted, and a PDDL *problem* arrives
    with its domain.
 *
 *  The pairing is not a guess: a problem says `(:domain blocks-domain)` and a
 *  domain says `(define (domain blocks-domain))`, so the right file is the one
 *  in the same directory that answers to that name. Picking a problem out of a
 *  list and being told to go and find its domain would be the picker asking
 *  the user to do its job.
*/
example_converted(Name, ConvName, Text, Diags) :-
	example_converted(Name, ConvName, Text, Diags, _Original).

%	An Inform 7 source opens as the Logical English story its assertions
%	make (docs/project/plans/InformPlan.md phase 4). The descriptions, which go in a
%	companion on the command line, do not travel here: the IDE opens one
%	document.
example_converted(Name, ConvName, Text, Diags, Original) :-
	example_path(Name, Path),
	exists_file(Path),
	file_name_extension(_, ni, Path), !,
	file_base_name(Path, Base),
	inform_converted(Path, Base, ConvName0, Text0, Diags),
	atom_string(ConvName, ConvName0),
	atom_string(Text, Text0),
	read_file_to_string(Path, Original, [encoding(utf8)]).
example_converted(Name, ConvName, Text, Diags, Original) :-
	example_path(Name, Path),
	exists_file(Path),
	file_name_extension(_, Ext, Path),
	memberchk(Ext, [pddl, drl]),
	read_file_to_string(Path, Src, [encoding(utf8)]),
	file_base_name(Path, Base),
	(   Ext == pddl, is_pddl_problem(f(Base, Src)), pddl_domain_file(Path, Src, DPath)
	->  file_base_name(DPath, DBase),
	    read_file_to_string(DPath, DSrc, [encoding(utf8)]),
	    Files = [f(DBase, DSrc), f(Base, Src)]
	;   Ext == drl, file_name_extension(Stem, _, Path), file_name_extension(Stem, wording, WPath),
	    exists_file(WPath)
	->  read_file_to_string(WPath, WSrc, [encoding(utf8)]),
	    file_base_name(WPath, WBase),
	    Files = [f(Base, Src), f(WBase, WSrc)]
	;   Files = [f(Base, Src)]
	),
	convert_files(Files, ConvName, Text, Diags),
	%  The source that was converted, verbatim, so the IDE can show it beside
	%  the translation. With two files it is both, labelled.
	findall(Part, ( member(f(FN, FS), Files),
			format(string(Part), '% ==== ~w ====\n~w', [FN, FS]) ), Parts),
	atomic_list_concat(Parts, '\n', Original0),
	atom_string(Original0, Original).

pddl_domain_file(Path, Src, DomainPath) :-
	pddl_declared_domain(Src, Name),
	file_directory_name(Path, Dir),
	directory_files(Dir, Files),
	member(F, Files),
	file_name_extension(_, pddl, F),
	atomic_list_concat([Dir, '/', F], DomainPath),
	DomainPath \== Path,
	exists_file(DomainPath),
	read_file_to_string(DomainPath, DSrc, [encoding(utf8)]),
	pddl_defines_domain(DSrc, Name), !.

%	`(:domain blocks-domain)` in a problem.
pddl_declared_domain(Src, Name) :-
	string_lower(Src, L),
	sub_string(L, B, _, _, ":domain"),
	Start is B + 7,
	sub_string(L, Start, _, 0, Rest),
	sub_string(Rest, E, 1, _, ")"),
	sub_string(Rest, 0, E, _, Raw),
	normalize_space(string(Name), Raw), Name \== "", !.

%	`(define (domain blocks-domain)` in a domain.
pddl_defines_domain(Src, Name) :-
	string_lower(Src, L),
	sub_string(L, B, _, _, "(domain"),
	Start is B + 7,
	sub_string(L, Start, _, 0, Rest),
	sub_string(Rest, E, 1, _, ")"),
	sub_string(Rest, 0, E, _, Raw),
	normalize_space(string(N), Raw),
	N == Name, !.

%	A name an example had before the example trees were regrouped
%	(LogicalEnglish2 docs/project/plans/NewExamplesStructure.md §4.3): links, the
%	documentation and videos keep working.
example_path(Name, Path) :-
	example_current_name(Name, New), New \== Name, !,
	example_path(New, Path).
example_path(Name, Path) :-
	lps_root(Root),
	member(Rel, ['/examples/', '/legacy_lps1/examples/',
		     '/legacy_lps1/examples/CLOUT_workshop/']),
	%  `.le` before `.lps`: where both exist the English is the document and
	%  the `.lps` its companion (docs/user/reference/le-for-lps.md §7), so `if/alice`
	%  must open alice.le, not alice.lps.
	member(Ext, ['', '.pl', '.le', '.lps', '.pddl', '.drl', '.ni']),
	atomic_list_concat([Root, Rel, Name, Ext], Path).
%	A bare `bank_transfer.le`, as a hand-typed link may say: the Logical
%	English examples (examples/le) answer to their file name too, after
%	everything else has been tried.
example_path(Name, Path) :-
	file_name_extension(_, le, Name),
	\+ sub_atom(Name, _, _, _, '/'),
	lps_root(Root),
	atomic_list_concat([Root, '/examples/le/', Name], Path).

%!	example_alias(?Old, ?New) is nondet.
%!	example_dir_alias(?OldDir, ?NewDir) is nondet.
%
%	Old example names (as ?example= takes them, with or without their
%	extension) and the names they have now; a directory alias renames every
%	example under it.
example_alias(goat_declarative, 'start/goat_declarative').
example_alias(blocks, 'start/blocks').
example_alias(blocks3d, 'start/blocks3d').
example_alias(lights, 'start/lights').
example_alias(thermostat, 'start/thermostat').

example_dir_alias(rkbook, 'collections/kowalski-book').
example_dir_alias(agent, 'agents/llm').
example_dir_alias(minecraft, 'agents/minecraft').
example_dir_alias(pddl, planning).
example_dir_alias(drools, 'migration/drools/drl').
example_dir_alias('doors/pddl', planning).
example_dir_alias('doors/drools', 'migration/drools/drl').

%!	example_current_name(+Name, -Current) is det.
example_current_name(Name, Current) :-
	(   file_name_extension(Base, Ext, Name), Ext \== '',
	    example_alias(Base, New)
	->  file_name_extension(New, Ext, Current)
	;   example_alias(Name, New)
	->  Current = New
	;   example_dir_alias(Old, NewDir),
	    atom_concat(Old, '/', OldSlash),
	    atom_concat(OldSlash, Rest, Name)
	->  atomic_list_concat([NewDir, '/', Rest], Current)
	;   Current = Name
	).

%	This file's own directory, two levels down from the repository root.
%	It asked lps_http.pl for it until the operations moved here — which
%	worked on a server and nowhere else: the WebAssembly build has no
%	lps_http.pl in it (it cannot load one), so every example lookup failed
%	with nothing to say for itself.
lps_root(Root) :-
	module_property(lps_api, file(F)),
	file_directory_name(F, Dir), file_directory_name(Dir, Src),
	file_directory_name(Src, Root).

/* Every example the server can offer, with a one-line description taken from
   the program's own first comment. 160 corpus programs plus ours: §I.10.1a
   asks for any of them to be two clicks from a run, and curation for the
   tutorial and the assistant needs the list before it can start. */
example_list(Examples) :-
	lps_root(Root),
	findall(E,
		( example_dir(Dir, DirName),
		  %  An example directory is normally relative to this
		  %  repository; the Logical English one is in another checkout
		  %  and arrives absolute.
		  ( sub_atom(Dir, 0, 1, _, '/') -> Full = Dir
		  ; atomic_list_concat([Root, '/', Dir], Full) ),
		  exists_directory(Full),
		  directory_files(Full, Files),
		  member(F, Files),
		  file_name_extension(_, Ext, F),
		  %  PDDL and Drools files are examples too: they open through the
		  %  same picker and arrive converted, which is what §IV.4 means by
		  %  a front end being a *door*.
		  memberchk(Ext, [pl, lps, pddl, drl, le, ni]),
		  %  A `.lps` beside a `.le` of the same name is that document's
		  %  companion (§7, the escape hatch of examples/le), and opens
		  %  with it, so it is not a second example.
		  \+ ( Ext == lps, file_name_extension(Base, lps, F),
		       file_name_extension(Base, le, LeF),
		       atomic_list_concat([Full, '/', LeF], LePath), exists_file(LePath) ),
		  \+ sub_atom(F, _, _, _, '_.P'),
		  atomic_list_concat([Full, '/', F], Path),
		  exists_file(Path),
		  example_rel(Dir, F, Rel),
		  example_title(Path, Title),
		  E0 = _{name: Rel, title: Title, dir: DirName, dirpath: Dir},
		  (   example_dir_blurb(Dir, Blurb)
		  ->  E = E0.put(dirblurb, Blurb)
		  ;   E = E0
		  ) ),
		Examples0),
	sort(name, @<, Examples0, Examples).

%	LPS2's own examples: examples/ and every folder under it that holds
%	programs, labelled by its README (examples/README.md). A new folder needs
%	a README, not a row here.
example_dir(Dir, Label) :-
	own_example_dir(Dir, Label).
example_dir('legacy_lps1/examples', 'corpus').
example_dir('legacy_lps1/examples/CLOUT_workshop', 'CLOUT workshop').
example_dir('legacy_lps1/examples/CLOUT_workshop/simulation', 'simulation').
example_dir('legacy_lps1/examples/forTesting', 'forTesting').
example_dir('legacy_lps1/examples/survival_game', 'survival game').

%!	own_example_dir(?Dir, ?Label) is nondet.
%
%	examples/ and its subdirectories, but those that hold no example of
%	their own making: a twin's sources/, a story's expected/ runs, phase0/
%	spikes, a Node project's node_modules/, logs/ and world/.
own_example_dir(Dir, Label) :-
	lps_root(Root),
	own_example_subdir(Root, examples, Dir),
	own_example_label(Dir, Label).

own_example_subdir(_, Dir, Dir).
own_example_subdir(Root, Dir, Sub) :-
	atomic_list_concat([Root, '/', Dir], Full),
	exists_directory(Full),
	directory_files(Full, Fs0), msort(Fs0, Fs),
	member(F, Fs),
	\+ sub_atom(F, 0, 1, _, '.'),
	\+ memberchk(F, [sources, expected, phase0, node_modules, logs, world]),
	atomic_list_concat([Full, '/', F], FullSub),
	exists_directory(FullSub),
	atomic_list_concat([Dir, '/', F], Sub0),
	own_example_subdir(Root, Sub0, Sub).

%	examples/ is LPS2; a twin (examples/migration/<source>/<twin>) is named
%	after its source; any other folder by the title of its README, up to
%	its ` — ` (docs: "Label — what it is"), or else by its name.
own_example_label(examples, 'LPS2') :- !.
own_example_label(Dir, Label) :-
	atomic_list_concat([examples, migration, Source, Twin], '/', Dir),
	\+ own_example_readme_title(Dir, _), !,
	atomic_list_concat([Source, ' twin: ', Twin], Label).
own_example_label(Dir, Label) :-
	(   own_example_readme_title(Dir, Title)
	->  (   sub_atom(Title, B, _, _, ' — ')
	    ->  sub_atom(Title, 0, B, _, Label)
	    ;   Label = Title
	    )
	;   file_base_name(Dir, Label)
	).

%!	example_folders(-Folders) is det.
%
%	Every example directory, with its label (and blurb), including those
%	holding only folders (examples/migration, "Migration twins"): the
%	picker nests a folder under the longest other one its path starts with,
%	as the landing page's tree does, so it needs the folders with no
%	program of their own too.
example_folders(Folders) :-
	lps_root(Root),
	findall(F,
		( example_dir(Dir, Label),
		  ( sub_atom(Dir, 0, 1, _, '/') -> Full = Dir
		  ; atomic_list_concat([Root, '/', Dir], Full) ),
		  exists_directory(Full),
		  F0 = _{dirpath: Dir, label: Label},
		  (   example_dir_blurb(Dir, Blurb)
		  ->  F = F0.put(blurb, Blurb)
		  ;   F = F0
		  ) ),
		Folders0),
	sort(dirpath, @<, Folders0, Folders).

%!	example_dir_blurb(+Dir, -Blurb) is semidet.
%
%	What a folder of examples is: its README title after the ` — `.
example_dir_blurb(Dir, Blurb) :-
	own_example_readme_title(Dir, Title),
	sub_atom(Title, B, L, _, ' — '), !,
	A is B + L,
	sub_atom(Title, A, _, 0, Blurb).

own_example_readme_title(Dir, Title) :-
	lps_root(Root),
	atomic_list_concat([Root, '/', Dir, '/README.md'], Readme),
	exists_file(Readme),
	catch(setup_call_cleanup(open(Readme, read, In, [encoding(utf8)]),
				 read_line_to_string(In, Line),
				 close(In)), _, fail),
	string(Line),
	split_string(Line, "", "# \t", [T]),
	T \== "",
	atom_string(Title, T).

%	A `.pddl` or `.drl` keeps its extension — that is what tells the reader,
%	and example_source/2, what it is — and its directory, like everything
%	else under examples/.
%	A `.le` under examples/ keeps its extension too: the name is what the
%	editor opens, and `if/world` used to open an empty untitled buffer
%	because nothing tried `.le` on the way back.
example_rel(Dir, F, Rel) :-
	file_name_extension(_, Ext, F), memberchk(Ext, [pddl, drl, ni, le]), !,
	(   atom_concat('examples/', Sub, Dir)
	->  atomic_list_concat([Sub, '/', F], Rel)
	;   Rel = F
	).
example_rel(examples, F, Rel) :- !, file_name_extension(Base, _, F), Rel = Base.
example_rel(Dir, F, Rel) :-
	atom_concat('legacy_lps1/examples/', Sub, Dir), !,
	file_name_extension(Base, _, F),
	( Sub == '' -> Rel = Base ; atomic_list_concat([Sub, '/', Base], Rel) ).
example_rel(Dir, F, Rel) :-
	file_name_extension(Base, _, F),
	atom_concat('examples/', Sub, Dir), !,
	atomic_list_concat([Sub, '/', Base], Rel).
example_rel(_, F, Rel) :- file_name_extension(Rel, _, F).

%	The first comment line of a program is its description, near enough: the
%	corpus writes one, and a program that does not gets its file name.
example_title(Path, Title) :-
	setup_call_cleanup(open(Path, read, S, [encoding(utf8)]),
			   first_comment(S, Title),
			   close(S)).

first_comment(S, Title) :-
	read_line_to_string(S, L),
	(   L == end_of_file
	->  Title = ""
	%  PDDL and DRL comment with `;` and `//`, and a converted example with no
	%  title showed as a bare em dash in the picker and on the start page.
	;   sub_string(L, 0, _, _, ";;")
	->  normalize_space(string(TP), L), strip_lead([";; ", "; "], TP, Title)
	;   sub_string(L, 0, _, _, ";")
	->  normalize_space(string(TP2), L), strip_lead(["; "], TP2, Title)
	;   sub_string(L, 0, _, _, "//")
	->  normalize_space(string(TD), L), strip_lead(["// "], TD, Title)
	;   sub_string(L, 0, _, _, "%")
	->  normalize_space(string(T1), L),
	    ( string_concat("% ", T, T1) -> Title = T ; Title = T1 )
	;   sub_string(L, 0, _, _, "/*")
	->  normalize_space(string(T2), L),
	    ( string_concat("/* ", T3, T2) -> Title = T3 ; Title = T2 )
	;   first_comment(S, Title)
	).

strip_lead([], T, T).
strip_lead([P|Ps], T0, T) :-
	( string_concat(P, T1, T0) -> T = T1 ; strip_lead(Ps, T0, T) ).

/*  The Prolog in a *program* — the one thing an HTTP endpoint compiles that it
    did not write. `/lpsapi` takes a program and runs it, and an LPS rule body
    may contain ordinary Prolog, so without this the endpoint is an open Prolog
    interpreter and the only thing standing between it and the machine is
    `LPS_TOKEN`. On by default here and nowhere else: the CLI runs your own
    file. `LPS_SANDBOX=0` turns it off for a deployment that trusts its
    callers. */
sandbox_diags(Program, Diags) :-
	(   sandbox_enabled([default(server)], true)
	->  catch(sandbox_check(Program, Diags), _, Diags = [])
	;   Diags = []
	).

%	Only the in-process transport can answer the editor-facing queries: they
%	are predicate calls, not part of the §2 payload the other two carry.
%	The templates a document declares, as the labelled surface strings
%	nl_to_le expects — it is told to produce instances of these and nothing
%	else, which is what keeps the model inside the program's own vocabulary.
le_templates_for(Program, Templates) :-
	(   lps_le_call(le_service:le_analyse_dict(Program, [], A)),
	    get_dict(templates, A, Ts)
	->  findall(S, ( member(T, Ts), get_dict(surface, T, S) ), Templates)
	;   Templates = []
	).

nl_issue_dict(I, D) :- ( is_dict(I) -> D = I ; term_string(I, S), D = _{message: S} ).

message_to_text_(E, S) :- format(string(S), '~q', [E]).

le_unavailable(_{ok: (false),
		 error: "the editor-facing Logical English queries need LE2 \c
			 loaded into this server: set LPS_LE2_LIB to a checkout"}).

%!	companion_source(+Dict, +Name, -CompanionName, -Source) is det.
%
%	What the request says the `.lps` companion of a Logical English document
%	is: `companion` its text, `companion_name` its name. A request carrying
%	neither gets the empty string, which is how every caller says "there is
%	no companion" — and the name is still derived, because the reply tells
%	the editor which file a companion diagnostic belongs to.
%!	solidity_program(+Source, +Name, -Program, -Templates, -Diags) is det.
%
%	The program to write as Solidity: a `.le` document through LE2 (its
%	templates give the contract its parameter names and comments), anything
%	else as LPS. Program is `none` when it does not compile; Diags then says
%	why.
solidity_program(Source, Name, Program, Templates, Diags) :-
	(   sub_atom(Name, _, _, 0, '.le')
	->  lps_le_translate_text(Source, Name, Text, Prov, LeDiags),
	    (   Text == ""
	    ->  Program = none, Templates = [], Diags = LeDiags
	    ;   lps_le_program_terms(Text, Name, Prov, "", '', Terms, ReadDiags),
		lps_compile(terms(Terms), internal, [dc], P, CDiags),
		append([LeDiags, ReadDiags, CDiags], Diags),
		catch(lps_le_templates(Source, Name, Templates), _, Templates = [])
	    )
	;   source_terms(Source, Terms0, ReadDiags),
	    lps_compile(terms(Terms0), legacy, [dc], P, CDiags),
	    append(ReadDiags, CDiags, Diags), Templates = []
	),
	(   var(Program)
	->  ( nonvar(P), P \== none, diags_ok(Diags) -> Program = P ; Program = none )
	;   true
	).

%	`foo.lps` -> `foo.le`: the name a converted document is offered under.
lps_to_le_name(Name, LEName) :-
	file_base_name(Name, Base),
	( file_name_extension(Stem, _, Base) -> true ; Stem = Base ),
	file_name_extension(Stem, le, LEName).

companion_source(Dict, Name, CName, Source) :-
	(   get_dict(companion, Dict, S), string(S), S \== ""
	->  Source = S
	;   Source = ""
	),
	(   get_dict(companion_name, Dict, CN), string(CN), CN \== ""
	->  atom_string(CName, CN)
	;   lps_le_companion_name(Name, CName)
	).

prov_dict(prov(I, F, L, C, K), _{index: I, file: FS, line: L, col: C, kind: KS}) :-
	atom_string(F, FS), atom_string(K, KS).

		 /*******************************
		 *	   operations		*
		 *******************************/

/*  Every request names an operation. One that does not is a client's mistake
    and is answered as one, like an operation this server does not have (the
    last `operation/3` clause).

    Failing here instead left the HTTP layer to answer 500 "goal unexpectedly
    failed", and told Sentry "the operation failed without an exception" with
    `operation: none` — a report that names nothing, can be acted on by
    nobody, and arrives whenever anything posts something that is not a
    request of ours: a curl probe, a scanner, a stale client. A *named*
    operation that fails without an exception is still reported, and now says
    which one.  */
handle(Dict, Reply) :-
	(   get_dict(operation, Dict, Op)
	->  operation(Op, Dict, Reply)
	;   Reply = _{ok: false,
		      error: "no operation in the request: POST /lpsapi takes a JSON \c
			      object with an `operation` field, and GET /lpsapi/status \c
			      says what this server is"}
	).

operation("compile", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(syntax, Dict, SyntaxS) -> atom_string(Syntax, SyntaxS) ; Syntax = legacy ),
	source_terms(Source, Terms0, ReadDiags),
	apply_provenance(Dict, Terms0, Terms),
	lps_compile(terms(Terms), Syntax, [dc], Program, CDiags),
	sandbox_diags(Program, SDiags),
	append(ReadDiags, CDiags, Diags0),
	append(Diags0, SDiags, Diags),
	maplist(diag_dict, Diags, DiagDicts),
	(   diags_ok(Diags)
	->  register_program(Program, Id),
	    Reply = _{ok: true, program: Id, diagnostics: DiagDicts}
	;   Reply = _{ok: false, diagnostics: DiagDicts}
	).
/*	Logical English (§I.9, M8f).

	Four operations, all of them thin wrappers over `src/edges/lps_le.pl`
	and therefore over whichever transport is configured — so the IDE is
	the same client whether LE2 is loaded into this image, reached over
	HTTP, or run as a subprocess, and there is no second origin for a
	browser to be told about.

	The division of labour is the interface contract's (§2): LE issues and
	LPS diagnostics are *concatenated, never merged*. They are different
	claims — "this sentence is not a template you declared" and "this
	program has an achieve without planning mode" — and an editor that
	blended them would be unable to say which half to trust when they
	disagree.
*/
operation("le_status", _Dict, Reply) :- !,
	lps_le_available(How),
	format(string(HowS), '~w', [How]),
	(   How == none
	->  Reply = _{ok: true, available: (false), how: HowS,
		      message: "Logical English is parsed by LE2. Set LPS_LE2_LIB \c
				to an LE2 checkout to load it into this server, \c
				LPS_LE2_URL to an LE2 endpoint, or LPS_LE2_DIR to \c
				run it as a subprocess."}
	;   ( lps_le_service_version(V) -> atom_string(V, VS) ; VS = null ),
	    Reply = _{ok: true, available: true, how: HowS, version: VS}
	).
operation("le_compile", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(name, Dict, N) -> atom_string(Name, N) ; Name = 'buffer.le' ),
	%  The `.lps` companion, if the editor has one open (§7 of
	%  docs/user/reference/le-for-lps.md). It arrives as text because the browser has no
	%  file system to look beside the document in; the CLI, which has, finds
	%  it for itself.
	companion_source(Dict, Name, CName, Companion),
	lps_le_translate_text(Source, Name, Text, Prov, LeDiags),
	maplist(diag_dict, LeDiags, IssueDicts),
	(   Text == ""
	->  Reply = _{ok: (false), lps: "", provenance: [], issues: IssueDicts,
		      diagnostics: []}
	;   %  The generated internal syntax, compiled here, so the editor gets
	    %  *our* diagnostics at *LE* coordinates — which is the whole point
	    %  of the provenance array.
	    lps_le_program_terms(Text, Name, Prov, Companion, CName, Terms0, ReadDiags),
	    le_max_time_override(Dict, Terms0, Terms),
	    lps_compile(terms(Terms), internal, [dc], Program, CDiags),
	    sandbox_diags(Program, SDiags),
	    append(ReadDiags, CDiags, Diags1),
	    append(Diags1, SDiags, Diags),
	    maplist(diag_dict, Diags, DiagDicts),
	    maplist(prov_dict, Prov, ProvDicts),
	    atom_string(CName, CNameS),
	    (   diags_ok(Diags)
	    ->  register_program(Program, Id),
		program_profile(Program, Profile),
		Reply = _{ok: true, program: Id, lps: Text, provenance: ProvDicts,
			  issues: IssueDicts, diagnostics: DiagDicts, profile: Profile,
			  companion: CNameS}
	    ;   Reply = _{ok: (false), lps: Text, provenance: ProvDicts,
			  issues: IssueDicts, diagnostics: DiagDicts,
			  companion: CNameS}
	    )
	).
/*  Misc > Convert to Logical English: an LPS program of the older,
    Prolog-like syntax, written as a Logical English document
    (src/syntax/lps_to_le.pl). The reply carries the document and everything
    the converter could not carry over, which the IDE shows before the new
    tab, because a converted program with a silent hole in it is worse than
    one that was never converted. */
operation("to_le", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(name, Dict, N) -> atom_string(Name, N) ; Name = 'buffer.lps' ),
	lps_to_le_name(Name, LEName),
	(   lps_to_le_ready(ok)
	->  lps_to_le_text(Source, Name, [], LEText, Diags),
	    maplist(diag_dict, Diags, DiagDicts),
	    atom_string(LEName, LENameS),
	    (	LEText == ""
	    ->	Reply = _{ok: (false), le: "", name: LENameS, diagnostics: DiagDicts}
	    ;	Reply = _{ok: true, le: LEText, name: LENameS, diagnostics: DiagDicts}
	    )
	;   lps_to_le_ready(Why), format(string(WhyS), '~w', [Why]),
	    Reply = _{ok: (false), le: "", name: "", diagnostics: [], message: WhyS}
	).

operation("le_lexicon", Dict, Reply) :- !,
	( get_dict(language, Dict, L) -> atom_string(Lang, L) ; Lang = en ),
	(   lps_le_call(le_service:le_lexicon_dict(Lang, Lex))
	->  Reply = Lex.put(ok, true)
	;   le_unavailable(Reply)
	).
/*  English in, Logical English out — LE2's `nl_to_le`, which asks a model for
    a fragment and then *verifies* it against the program before handing it
    over, refining up to twice against the issues its own splice introduced.
    The model and the keys are the IDE's, because LE2's client is brokered
    (llm/le_llm.pl) and we register ours when the library loads.

    Like the live panel's translator, the result is *shown*, not applied: a
    mistranslated sentence is a sentence the author did not write.  */
operation("le_nl", Dict, Reply) :- !,
	get_dict(sentence, Dict, Sentence),
	( get_dict(source, Dict, Program) -> true ; Program = "" ),
	( get_dict(kind, Dict, K0), K0 == "query" -> Kind = query ; Kind = facts ),
	( get_dict(api_keys, Dict, Keys) -> true ; Keys = _{} ),
	( get_dict(model, Dict, M), M \== null -> Model = M ; assistant_default_model(Keys, Model) ),
	(   \+ lps_le_call(true)
	->  le_unavailable(Reply)
	;   le_templates_for(Program, Templates),
	    ( assistant_key_for(Model, Keys, Key) -> true ; Key = '' ),
	    (   catch(lps_le_call(le_service:le_english_to_le(Kind, Sentence, Templates,
							     Program, Model,
							     [api_key(Key), timeout(120)],
							     LEText, Issues)),
		      E, (message_to_text_(E, EM), LEText = none))
	    ->	true
	    ;	LEText = none, EM = "the conversion failed"
	    ),
	    (   LEText == none
	    ->  Reply = _{ok: (false), error: EM}
	    ;   maplist(nl_issue_dict, Issues, IssueDicts),
		text_to_string(LEText, S),
		Reply = _{ok: true, le: S, issues: IssueDicts}
	    )
	).
operation("le_analyse", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	(   lps_le_call(le_service:le_analyse_dict(Source, [], A))
	->  Reply = A.put(ok, true)
	;   le_unavailable(Reply)
	).
/*  The legal view of a Logical English LPS document: LE2's le_lps_legal.pl,
    a fixed transformation of the program's own laws and constraints into a
    timeless LE program — who may do what, when, with which effect. It is
    answered by LE2's query engine, not ours, so the IDE opens it as a
    document for the LE editor to read; running it is LE2's business.  */
operation("le_legal_view", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(name, Dict, N) -> atom_string(Name, N) ; Name = 'buffer.le' ),
	(   \+ lps_le_call(true)
	->  le_unavailable(Reply)
	;   (   legal_view_run(Dict, Source, Name, Run),
	        lps_le_call(le_service:le_legal_view(Source, [Run], Text, Issues))
	    ->  true
	    ;   lps_le_call(le_service:le_legal_view(Source, Text, Issues))
	    )
	->  findall(M, ( member(issue(_, _, M0), Issues), format(string(M), '~w', [M0]) ), Ms),
	    Reply = _{ok: true, source: Text, notes: Ms}
	;   Reply = _{ok: (false), error: "No legal view: the document does not \c
					  declare the target language lps, or does not load."}
	).
operation("session_new", Dict, Reply) :- !,
	program_of(Dict, Program),
	lps_session_new(Program, [dc], S),
	register_session(S, Id),
	Reply = _{ok: true, session: Id}.
operation("observe", Dict, Reply) :- !,
	session_of(Dict, Id, S0),
	get_dict(events, Dict, EventStrings),
	maplist(parse_term_string, EventStrings, Events),
	lps_session_observe(S0, Events, S),
	update_session(Id, S),
	Reply = _{ok: true, session: Id}.
operation("step", Dict, Reply) :- !,
	session_of(Dict, Id, S0),
	lps_session_step(S0, S, Report),
	update_session(Id, S),
	report_dict(Report, RD),
	lps_session_status(S, Status),
	format(string(StatusS), '~w', [Status]),
	Reply = _{ok: true, session: Id, status: StatusS, cycle: RD}.
operation("run", Dict, Reply) :- !,
	session_of(Dict, Id, S0),
	( get_dict(cycles, Dict, N) -> Stop = cycles(N) ; Stop = end ),
	get_time(T0),
	lps_session_run(S0, Stop, S, _),
	get_time(T1),
	update_session(Id, S),
	lps_session_status(S, Status), lps_session_time(S, Time),
	format(string(StatusS), '~w', [Status]),
	Ms is round((T1 - T0) * 1000),
	stop_phrase(S, Status, Reason),
	Reply = _{ok: true, session: Id, status: StatusS, cycle: Time,
		  ms: Ms, reason: Reason}.
operation("state", Dict, Reply) :- !,
	session_of(Dict, _, S),
	lps_session_state(S, Fluents),
	maplist(term_string_, Fluents, Strings),
	Reply = _{ok: true, fluents: Strings}.
operation("fork", Dict, Reply) :- !,
	session_of(Dict, _, S),
	lps_session_fork(S, S2),
	register_session(S2, Id2),
	Reply = _{ok: true, session: Id2, kind: "hypothetical"}.
operation("discard", Dict, Reply) :- !,
	get_dict(session, Dict, IdS), atom_string(Id, IdS),
	with_mutex(lps_http_sessions, retractall(registered_session(Id, _, _))),
	Reply = _{ok: true}.
operation("trace", Dict, Reply) :- !,
	session_of(Dict, _, S),
	lps_session_trace(S, Trace),
	findall(D, ( member(stage(St, C, I), Trace), stage_dict(St, C, I, D) ), Ds),
	Reply = _{ok: true, trace: Ds}.
operation("dump", Dict, Reply) :- !,
	program_of(Dict, Program),
	with_output_to(string(S), dump_internal(Program, current_output)),
	Reply = _{ok: true, dump: S}.
%	Examples are served rather than embedded in the page. Embedding meant
%	escaping Prolog inside a JavaScript template literal inside HTML, and the
%	first casualty was `O1 \= O2` arriving as `O1 \\= O2` — a program that
%	looks right, does not parse, and was being offered as the thing to try.
operation("example", Dict, Reply) :- !,
	( get_dict(name, Dict, N) -> true ; N = "start/goat_declarative" ),
	atom_string(Name, N),
	(   example_converted(Name, CName, Text, Diags, Original)
	->  maplist(diag_dict, Diags, DD),
	    Reply = _{ok: true, name: CName, source: Text, converted_from: N,
		      original: Original, diagnostics: DD}
	;   example_source(Name, FileName, Text)
	->  (   example_companion(Name, CompName, CompText)
	    ->  Reply0 = _{ok: true, name: FileName, source: Text,
			  companion_name: CompName, companion: CompText}
	    ;	Reply0 = _{ok: true, name: FileName, source: Text}
	    ),
	    (   example_originals(Name, Origin, OText)
	    ->  Reply = Reply0.put(_{converted_from: Origin, original: OText})
	    ;   Reply = Reply0
	    )
	;   format(string(M), 'no such example: ~w', [Name]),
	    Reply = _{ok: false, error: M}
	).
%	Where an `includes these resources:` item of a Logical English document
%	leads — the editor's "Show definition" on that line. A URL is returned
%	for the browser to open; a local resource arrives as an example does,
%	with its companion, so the editor opens it in a tab. The document's
%	name and text come along because that is what the compiler resolves the
%	include against (lps_le_resolve_resource/4).
operation("resource", Dict, Reply) :- !,
	( get_dict(name, Dict, N0) -> atom_string(Name, N0) ; Name = '' ),
	( get_dict(source, Dict, Src) -> true ; Src = "" ),
	(   get_dict(resource, Dict, R0), string(R0), R0 \== ""
	->  lps_le:lps_le_resolve_resource(Name, Src, R0, Where),
	    (   Where = url(URL)
	    ->  Reply = _{ok: true, kind: "url", url: URL}
	    ;   Where = file(Path)
	    ->  read_file_to_string(Path, Text, [encoding(utf8)]),
		file_base_name(Path, Base), atom_string(Base, FileName),
		lps_root(Root), atom_concat(Root, '/', RootDir), atom_concat(RootDir, Rel, Path),
		(   file_name_extension(Stem, le, Path),
		    file_name_extension(Stem, lps, CPath), exists_file(CPath)
		->  read_file_to_string(CPath, CText, [encoding(utf8)]),
		    file_base_name(CPath, CBase), atom_string(CBase, CName),
		    Reply = _{ok: true, kind: "file", name: FileName, path: Rel, source: Text,
			      companion_name: CName, companion: CText}
		;   Reply = _{ok: true, kind: "file", name: FileName, path: Rel, source: Text}
		)
	    ;   Where = missing(Path)
	    ->  format(string(M), "no such resource: ~w (looked for ~w)", [R0, Path]),
		Reply = _{ok: false, error: M}
	    ;   Where = outside(Path)
	    ->  format(string(M), "~w resolves to ~w, outside this repository, which the server does not serve", [R0, Path]),
		Reply = _{ok: false, error: M}
	    )
	;   Reply = _{ok: false, error: "resource: which resource?"}
	).
operation("analyse", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(syntax, Dict, SyntaxS) -> atom_string(Syntax, SyntaxS) ; Syntax = legacy ),
	source_terms(Source, Terms0, ReadDiags),
	apply_provenance(Dict, Terms0, Terms),
	lps_compile(terms(Terms), Syntax, [dc], P, CDiags),
	sandbox_diags(P, SDiags),
	append(ReadDiags, CDiags, Diags0),
	append(Diags0, SDiags, Diags),
	maplist(diag_dict, Diags, DiagDicts),
	program_profile(P, Profile),
	Reply = _{ok: true, diagnostics: DiagDicts, profile: Profile}.
operation("explain", Dict, Reply) :- !,
	session_of(Dict, _, S),
	get_dict(question, Dict, QS),
	parse_term_string(QS, Question),
	lps_session_explain(S, Question, explanation(_, Verdict, Tree)),
	node_dict(Tree, TreeDict),
	format(string(V), '~w', [Verdict]),
	Reply = _{ok: true, verdict: V, tree: TreeDict}.
operation("timeline", Dict, Reply) :- !,
	session_of(Dict, _, S),
	lps_session_timeline(S, timeline(Max, FluentLanes, EventLane, CompositeLane)),
	maplist(fluent_lane_dict, FluentLanes, FL),
	stage_lane_dict(EventLane, EL),
	stage_lane_dict(CompositeLane, CL),
	lps_session_refused(S, Refused),
	findall(_{cycle: C, items: Items, conditions: CS},
		( member(refused(C, Es, Conds), Refused),
		  maplist(term_string_, Es, Items),
		  with_output_to(string(CS), print(Conds)) ),
		RD),
	%  a fluent declared with a default holds it for every key with no
	%  stored entry: one line says so, below the stored entries' lanes
	lps_session_program(S, P),
	p_defaults(P, Defaults),
	findall(DS, ( member(D, Defaults), \+ scalar_always_stored(D, FluentLanes, Max),
		      default_string(D, DS) ), DD),
	Reply = _{ok: true, cycles: Max, fluents: FL, events: EL, composites: CL, refused: RD,
		  defaults: DD}.
operation("changes", Dict, Reply) :- !,
	session_of(Dict, _, S),
	get_dict(cycle, Dict, C),
	lps_session_changes(S, C, changes(_, I, T, U, Persisted)),
	maplist(change_dict, I, ID), maplist(change_dict, T, TD), maplist(change_dict, U, UD),
	maplist(term_string_, Persisted, PD),
	Reply = _{ok: true, cycle: C, initiated: ID, terminated: TD, updated: UD, persisted: PD}.
operation("live_start", Dict, Reply) :- !,
	program_of(Dict, Program),
	findall(O, ( get_dict(cycle_ms, Dict, Ms), O = cycle_ms(Ms)
		   ; get_dict(channels, Dict, Ch), O = channels(Ch) ), Opts),
	live_start(Program, Opts, Id),
	Reply = _{ok: true, live: Id}.
operation("live_status", Dict, Reply) :- !,
	live_id(Dict, Id), live_status(Id, Reply).
operation("live_observe", Dict, Reply) :- !,
	live_id(Dict, Id),
	get_dict(events, Dict, Events),
	( get_dict(channel, Dict, C) -> atom_string(Channel, C) ; Channel = any ),
	live_observe(Id, Channel, Events, Reply).
operation("live_verbose", Dict, Reply) :- !,
	live_id(Dict, Id),
	( get_dict(verbose, Dict, V) -> true ; V = (false) ),
	( V == true -> B = true ; B = (false) ),
	live_command(Id, verbose(B)), Reply = _{ok: true}.
operation("live_pause", Dict, Reply) :- !,
	live_id(Dict, Id), live_command(Id, pause), Reply = _{ok: true}.
operation("live_resume", Dict, Reply) :- !,
	live_id(Dict, Id), live_command(Id, resume), Reply = _{ok: true}.
operation("live_step", Dict, Reply) :- !,
	live_id(Dict, Id), live_command(Id, step), Reply = _{ok: true}.
operation("live_stop", Dict, Reply) :- !,
	live_id(Dict, Id), live_command(Id, stop), Reply = _{ok: true}.
operation("live_scene", Dict, Reply) :- !,
	live_id(Dict, Id),
	( get_dict(kind, Dict, "3d") -> Decl = display3d ; Decl = display ),
	(   live_scene(Id, Decl, Cycle, scene(_, Timeless0, Items))
	->  scene_objects(Timeless0, Timeless),
	    maplist(props_dict, Timeless, TL),
	    maplist(visual_dict, Items, IV),
	    %  A viewer that polls the scene also needs to know whether the
	    %  session is paused (so Pause can look like it did something) and
	    %  which mouse events the program will accept.
	    live_flags(Id, Paused, Status),
	    live_mouse_kinds(Id, Mouse0),
	    maplist([N, S2]>>atom_string(N, S2), Mouse0, Mouse),
	    Reply = _{ok: true, cycle: Cycle, timeless: TL, items: IV,
		      paused: Paused, status: Status, mouse: Mouse}
	;   Reply = _{ok: false, error: "no such live session"}
	).
operation("live_translate", Dict, Reply) :- !,
	live_id(Dict, Id),
	get_dict(text, Dict, Text),
	(   live_session(Id, S)
	->  lps_session_program(S, P),
	    ( get_dict(api_keys, Dict, Keys) -> true ; Keys = _{} ),
	    ( get_dict(model, Dict, M) -> true ; M = null ),
	    ( get_dict(channel, Dict, C0), atom_string(Ch, C0),
	      lps_live:live_allowed(Id, Ch, Allowed)
	    -> Extra = [allowed(Allowed)] ; Extra = [] ),
	    assistant_translate(P, Text, [keys(Keys), model(M)|Extra], Events),
	    Reply = _{ok: true, events: Events}
	;   Reply = _{ok: false, error: "no such live session"}
	).
/*	Playing a story (docs/project/plans/InformPlan.md phase 2): src/edges/lps_play.pl.
	`play_start` takes a `file`, or `source` and `name` with an optional
	`companion` — the same shapes `le_compile` takes; the reply carries the
	opening lines and the events the player's channel may carry. Every
	turn is `play_turn` with the typed `text`; `play_why` asks about the
	last turn (`question: "last"`) or any question form. */
operation("play_start", Dict, Reply) :- !,
	( get_dict(api_keys, Dict, Keys) -> true ; Keys = _{} ),
	( get_dict(model, Dict, M) -> true ; M = null ),
	(   get_dict(file, Dict, FileS), FileS \== null, FileS \== ""
	->  atom_string(File, FileS), Source = file(File)
	;   get_dict(source, Dict, Src),
	    ( get_dict(name, Dict, N) -> atom_string(Name, N) ; Name = 'story.le' ),
	    companion_source(Dict, Name, CName, Companion),
	    Source = text(Src, Name, Companion, CName)
	),
	catch(( lps_play:play_start(Source, [keys(Keys), model(M)], Id), Failed = none ),
	      play_failed(Ds), Failed = Ds),
	(   Failed == none
	->  lps_play:play_status(Id, St),
	    ( St.transcript = [Opening|_] -> Lines = Opening.lines ; Lines = [] ),
	    play_with_session(Id, _{ok: true, play: Id, lines: Lines, allowed: St.allowed}, Reply)
	;   maplist(diag_dict, Failed, DD),
	    Reply = _{ok: false, error: "the story did not compile", diagnostics: DD}
	).
operation("play_turn", Dict, Reply) :- !,
	play_id(Dict, Id),
	get_dict(text, Dict, Text),
	lps_play:play_turn(Id, Text, Reply0),
	play_with_session(Id, Reply0, Reply).
operation("play_why", Dict, Reply) :- !,
	play_id(Dict, Id),
	( get_dict(question, Dict, Q0) -> true ; Q0 = "last" ),
	(   Q0 == "last"
	->  Q = last
	;   catch(term_string(Q, Q0), _, Q = last)
	),
	catch(( lps_play:play_why(Id, Q, Lines), Err = none ), E, format(string(Err), "~q", [E])),
	(   Err == none
	->  Reply = _{ok: true, lines: Lines}
	;   Reply = _{ok: false, error: Err}
	).
operation("play_status", Dict, Reply) :- !,
	play_id(Dict, Id), lps_play:play_status(Id, Reply0),
	( Reply0.ok == true -> play_with_session(Id, Reply0, Reply) ; Reply = Reply0 ).
operation("play_fork", Dict, Reply) :- !,
	play_id(Dict, Id),
	(   lps_play:play_fork(Id, Id2)
	->  play_with_session(Id2, _{ok: true, play: Id2, parent: Id}, Reply)
	;   Reply = _{ok: false, error: "no such game"}
	).
operation("play_diff", Dict, Reply) :- !,
	play_id(Dict, Id),
	( get_dict(other, Dict, OS) -> atom_string(Other, OS) ; Other = none ),
	(   lps_play:play_diff(Id, Other, Lines)
	->  Reply = _{ok: true, lines: Lines}
	;   Reply = _{ok: false, error: "no such game"}
	).
operation("play_commands", Dict, Reply) :- !,
	play_id(Dict, Id),
	(   lps_play:play_commands(Id, Cs)
	->  Reply = _{ok: true, commands: Cs}
	;   Reply = _{ok: false, error: "no such game"}
	).
operation("play_guess", Dict, Reply) :- !,
	play_id(Dict, Id),
	get_dict(text, Dict, Text0), text_to_string(Text0, Text),
	lps_play:play_guess(Id, Text, Reply).
operation("play_last_change", Dict, Reply) :- !,
	play_id(Dict, Id),
	get_dict(term, Dict, Term0), text_to_string(Term0, Term),
	( get_dict(cycle, Dict, Before), integer(Before) -> true ; Before = 1000000 ),
	lps_play:play_last_change(Id, Term, Before, Reply).
operation("play_list", _Dict, Reply) :- !,
	lps_play:play_list(Games), Reply = _{ok: true, games: Games}.
operation("play_stop", Dict, Reply) :- !,
	play_id(Dict, Id), lps_play:play_stop(Id), Reply = _{ok: true}.
operation("assistant_models", Dict, Reply) :- !,
	( get_dict(api_keys, Dict, Keys) -> true ; Keys = _{} ),
	%  `refresh: true` asks the providers again, now, rather than using what
	%  was read at startup — for the case where a key was just pasted in.
	( get_dict(refresh, Dict, true) -> catch(models_refresh(Keys), _, true) ; true ),
	lps_assistant:assistant_models(Keys, Models),
	Reply = _{ok: true, models: Models}.
operation("assistant_command", Dict, Reply) :- !,
	assistant_start(Dict, Job),
	Reply = _{ok: true, job: Job}.
/*  `new_companion` is not optional: a Logical English document keeps its
    `display/2` clauses in its `.lps` companion (le-for-lps.md §7), so for a
    `.le` buffer the animation IS the companion and the document does not
    change at all. Leaving it out of this reply meant "Animate in 2D" on any
    Logical English program ended with an *Apply to editor* button that applied
    nothing — the browser reads exactly this field (ui/src/assistant.js,
    pendingEdit). It passed every gate because ide_check.cjs stubs the reply
    with the field the server never sent.  */
operation("assistant_status", Dict, Reply) :- !,
	get_dict(job, Dict, JobS), atom_string(Job, JobS),
	assistant_status(Job, S),
	Reply = _{ok: true, status: S.status, output: S.output,
		  explanation: S.explanation, new_content: S.new_content,
		  new_companion: S.new_companion,
		  error: S.error}.
operation("assistant_interrupt", Dict, Reply) :- !,
	get_dict(job, Dict, JobS), atom_string(Job, JobS),
	assistant_interrupt(Job),
	Reply = _{ok: true}.
/*  `runtime` matters more than it looks. The page is opened from a `blob:` URL,
    and a *relative* script src in a blob resolves against the blob's own opaque
    origin — so the default `/assets/swipl/swipl-web.js` silently 404s and the
    page reports `Can't find variable: SWIPL`. The client therefore sends an
    absolute URL, and the same URL is what makes a *downloaded* copy work
    without a copy of the runtime beside it. */
operation("wasm_bundle", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(title, Dict, T) -> Title = T ; Title = "an LPS program" ),
	findall(O, ( get_dict(runtime, Dict, R), R \== "", O = runtime(R) ), Opts0),
	wasm_bundle(Source, [title(Title)|Opts0], Html),
	Reply = _{ok: true, html: Html}.
/* Misc ▸ Deploy as Solidity (lpsPlus's lps_solidity.pl, loaded by
   ../syntax/lps_plus.pl): the program in the
   editor — LPS, or Logical English for LPS — as a Solidity contract, or the
   list of what forbids a straight translation, each with its line. The
   sandbox the IDE opens the contract in is named here too, so the client does
   not hard-code a third party's address.
*/
operation("to_solidity", _Dict, Reply) :-
	\+ lps_plus_available(solidity), !,
	lps_plus_message(solidity, M), atom_string(M, MS),
	Reply = _{ok: (false), error: MS}.
operation("to_solidity", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(name, Dict, N) -> atom_string(Name, N) ; Name = 'buffer.lps' ),
	solidity_program(Source, Name, Program, Templates, Diags),
	(   Program == none
	->  maplist(diag_dict, Diags, DD),
	    Reply = _{ok: true, compatible: (false), compiled: (false), problems: DD}
	;   lps_solidity:lps_to_solidity(Program, [templates(Templates), source(Source), origin(Name)], R),
	    lps_solidity:solidity_sandbox(name, SName), lps_solidity:solidity_sandbox(base, SBase),
	    (   R = solidity(Text, Contract, Notes)
	    ->  maplist(diag_dict, Notes, ND),
		lps_solidity:solidity_sandbox_url(Text, URL),
		atom_string(Contract, CS),
		Reply = _{ok: true, compatible: true, solidity: Text, contract: CS, notes: ND,
			  sandbox: _{name: SName, base: SBase, url: URL}}
	    ;   R = refused(Ps),
		maplist(diag_dict, Ps, PD),
		Reply = _{ok: true, compatible: (false), compiled: true, problems: PD,
			  sandbox: _{name: SName, base: SBase}}
	    )
	).
/* Open a PDDL domain-and-problem or a Drools rule base as if it were an LPS
   program (§IV.4). The point of a front end is that it is a *door*, not a
   fork: the file arrives through File ▸ Open like any other, comes back as
   internal syntax with a header saying what it was and when it was converted,
   and everything downstream — the panes, the assistant, the explanations —
   works on it unchanged.

   `files` carries every file the user opened at once, because a PDDL problem
   without its domain is not a program and asking for them one at a time would
   be a worse conversation than reading both.
*/
/* The formats LE2's translators read (File ▸ Open offers their extensions)
   and write (Misc ▸ Export to Another System…, for a Logical English
   document). Both empty without LE2 in this process. */
/* Which of the translators that live outside this repository (lpsPlus:
   ../syntax/lps_plus.pl) this server has: the IDE asks once, so that a menu
   item whose translator is absent is shown disabled with the reason rather
   than failing when it is chosen. The `.drl` door needs no entry here — it is
   already visible in `import_formats`, which offers the extension only where
   the reader is installed. */
operation("capabilities", _Dict, Reply) :- !,
	(   lps_plus_available(solidity)
	->  Reply = _{ok: true, solidity: true}
	;   lps_plus_message(solidity, M), atom_string(M, MS),
	    Reply = _{ok: true, solidity: (false), solidity_why: MS}
	).
operation("import_formats", _Dict, Reply) :- !,
	(   lps_le_call(le_service:le_import_formats(Fs)) -> true ; Fs = [] ),
	findall(F, lps2_import_format(F), Own),
	Reply = _{ok: true, formats: Fs, lps2_formats: Own}.
operation("export_formats", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	(   lps_le_call(le_service:le_export_formats(Source, [], Fs)) -> true ; Fs = [] ),
	Reply = _{ok: true, formats: Fs}.
operation("export", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	get_dict(exporter, Dict, Id),
	(   \+ lps_le_call(true)
	->  le_unavailable(Reply)
	;   lps_le_call(le_service:le_export(Source, Id, [], R0))
	->  (   get_dict(error, R0, _)
	    ->  %  refused (the program uses something the target cannot say):
	        %  the problems, each with its line, travel with the error
	        Reply = R0.put(ok, (false))
	    ;   Reply = R0.put(ok, true)
	    )
	;   Reply = _{ok: (false), error: "the exporter failed"}
	).
%	With `files` (every file File ▸ Open was given), `programs` has one reply
%	per program they make (convert_groups/2).
operation("convert", Dict, Reply) :-
	get_dict(files, Dict, Fs), is_list(Fs), !,
	convert_inputs(Dict, Files),
	convert_groups(Files, Groups),
	maplist(convert_group_reply, Groups, Programs),
	Reply = _{ok: true, programs: Programs}.
operation("convert", Dict, Reply) :- !,
	convert_inputs(Dict, Files),
	(   catch(convert_files(Files, Name, Source, Diags), _, fail)
	->  maplist(diag_dict, Diags, DD),
	    Reply = _{ok: true, name: Name, source: Source, diagnostics: DD}
	;   Reply = _{ok: false, error: "nothing here to convert: expected .pddl, .drl, or a file a translator of the Logical English installation reads"}
	).
operation("list_examples", _Dict, Reply) :- !,
	example_list(Examples),
	example_folders(Folders),
	Reply = _{ok: true, examples: Examples, folders: Folders}.
operation("scene3d", Dict, Reply) :- !,
	session_of(Dict, _, S),
	get_dict(cycle, Dict, C),
	lps_session_scene(S, C, display3d, scene(_, Timeless0, Items)),
	scene_objects(Timeless0, Timeless),
	maplist(props_dict, Timeless, TL),
	maplist(visual_dict, Items, IV),
	Reply = _{ok: true, cycle: C, timeless: TL, items: IV}.
operation("scene", Dict, Reply) :- !,
	session_of(Dict, _, S),
	get_dict(cycle, Dict, C),
	lps_session_scene(S, C, scene(_, Timeless0, Items)),
	scene_objects(Timeless0, Timeless),
	maplist(props_dict, Timeless, TL),
	maplist(visual_dict, Items, IV),
	Reply = _{ok: true, cycle: C, timeless: TL, items: IV}.
/*  What is worth drawing of this run (AnimationPlan.md §5): the fluents that
    discriminate the states, the cycles worth a frame, and the states the run
    comes back to. Read off the trace, so it costs a projection of the
    automaton and no guesswork at all — the scene panes offer "next change"
    from it, `scenes` keys its strip on it, and the assistant is told it
    before it plans.  */
operation("focus", Dict, Reply) :- !,
	session_of(Dict, _, S),
	lps_session_focus(S, focus(Disc, Keyframes, Loops)),
	maplist(disc_dict, Disc, DD),
	maplist(keyframe_dict, Keyframes, KD),
	Reply = _{ok: true, discriminating: DD, keyframes: KD, loops: Loops}.
/*  The run as a STRIP of scenes (AnimationPlan.md §7): one picture per cycle
    at which the picture becomes a different picture, in order, each with what
    moved the story on to it.

    This is a *diagram of the run* rather than an animation of it, and it is
    what a reader wants when asking "what happened?" rather than "what is true
    now?". The frames are the focus's keyframes (§5) — the states, not the
    cycles — so a forty-cycle run of six states is six pictures and not forty.
    The caption is computed, not written: the events at that cycle and the
    fluents that began, ended or changed value with them, which is exactly
    what `lps_session_changes/3` has.

    Capped at 24 frames: past that it is a filmstrip nobody reads, and the
    reply carries `more` so the IDE can say so.
*/
operation("scenes", Dict, Reply) :- !,
	session_of(Dict, _, S),
	( get_dict(kind, Dict, "3d") -> Decl = display3d, K = "3d" ; Decl = display, K = "2d" ),
	lps_session_focus(S, focus(_, KFs0, _)),
	length(KFs0, NAll),
	( NAll > 24 -> length(KFs, 24), append(KFs, _, KFs0), More is NAll - 24
	; KFs = KFs0, More = 0 ),
	findall(F, ( member(KF, KFs), scene_frame(S, Decl, KF, F) ), Frames),
	lps_session_time(S, Max),
	Reply = _{ok: true, kind: K, cycles: Max, frames: Frames, more: More}.
operation("automaton", Dict, Reply) :- !,
	session_of(Dict, _, S),
	findall(O, ( member(O, [abstract_numbers, non_reflexive]),
		     get_dict(O, Dict, true) ), Opts),
	lps_session_automaton(S, Opts, automaton(Nodes, Edges)),
	maplist(automaton_node_dict, Nodes, ND),
	maplist(automaton_edge_dict, Edges, ED),
	Reply = _{ok: true, states: ND, transitions: ED}.
operation(Op, _, _{ok: false, error: Msg}) :-
	format(string(Msg), 'unknown operation: ~w', [Op]).

/*  The program's run, for its legal view: the state at each time and the
    events that happened from T-1 to T (the `fluents` and `events` records
    of the trace), which make the view's scenarios the states before each
    call of the program's own scenario and its questions whether each call
    may be made. Fails when the program does not compile or run; the view is
    then drawn without them.  */
legal_view_run(Dict, Source, Name, run(States, Happened)) :-
	companion_source(Dict, Name, CName, Companion),
	lps_le_translate_text(Source, Name, Text, Prov, _),
	Text \== "",
	lps_le_program_terms(Text, Name, Prov, Companion, CName, Terms, _),
	lps_compile(terms(Terms), internal, [dc], Program, Diags),
	diags_ok(Diags),
	lps_session_new(Program, [dc], S0),
	catch(call_with_time_limit(20, lps_session_run(S0, end, S, _)), _, fail),
	lps_session_trace(S, Trace),
	findall(T-Fs, member(stage(fluents, T, Fs), Trace), States),
	findall(T-Es, member(stage(events, T, Es), Trace), Happened).

/*  A game's session, where the panes can find it. The timeline, the 2D and
    3D scenes and the automaton all read a *registered* session by id; a
    game keeps its own session term, so after every turn the game's current
    term is registered under one id per game (registered once, updated
    after), and the reply carries the id and the last recorded cycle. The
    panel sets them as a run would, and the panes follow the play. */
:- dynamic play_http_session/2.        % PlayId, SessionId

play_with_session(Id, Reply0, Reply) :-
	(   lps_play:game(Id, G), get_dict(session, G, S)
	->  (   play_http_session(Id, SId)
	    ->  update_session(SId, S)
	    ;   register_session(S, SId),
		with_mutex(lps_http_sessions, assertz(play_http_session(Id, SId)))
	    ),
	    lps_session_time(S, T), Last is max(0, T - 1),
	    atom_string(SId, SIdS),
	    Reply = Reply0.put(_{session: SIdS, cycle: Last})
	;   Reply = Reply0
	).

play_id(Dict, Id) :-
	( get_dict(play, Dict, S) -> atom_string(Id, S) ; Id = none ).

live_id(Dict, Id) :-
	get_dict(live, Dict, S), atom_string(Id, S).

		 /*******************************
		 *	    registry		*
		 *******************************/

program_of(Dict, Program) :-
	get_dict(program, Dict, IdS), atom_string(Id, IdS),
	(   with_mutex(lps_http_sessions, registered_program(Id, Program))
	->  true
	;   throw(error(lps_no_such_program(Id), _))
	).

/*  The toolbar's maxTime, for a run of a Logical English document.

    A number typed over the toolbar's maxTime wins over the program's own for
    that run, without editing the buffer. For the internal and legacy syntaxes
    the IDE rewrites the text it sends (`sourceForRun`); a Logical English
    document is compiled from its tabs, by LE2, so the number travels as
    `max_time` and replaces the `maxTime/1` the English generated (the
    maximum time is N), or is added when there is none. Without it the field
    was silently ignored for every .le story. */
le_max_time_override(Dict, Terms0, Terms) :-
	get_dict(max_time, Dict, N), integer(N), N > 0, !,
	(   selectchk(t(maxTime(_), Src), Terms0, Rest)
	->  exclude([t(T, _)]>>(T = maxTime(_)), Rest, Rest1),
	    Terms = [t(maxTime(N), Src)|Rest1]
	;   Terms0 = [t(_, Src)|_]
	->  Terms = [t(maxTime(N), Src)|Terms0]
	;   Terms = [t(maxTime(N), unknown)]
	).
le_max_time_override(_, Terms, Terms).

/*  `prog_id/2` is the module the compiler made — `lps_prog_7`, from a counter
    in `src/core/`, where no tag can be minted because §I.2.4 forbids core the
    randomness to mint one with. So the tag goes on here, at the edge, where the
    id becomes a thing a stranger holds. What crosses the wire is this id and
    nothing else: two replies produce it and `program_of/2` consumes it, so the
    two need only agree with each other.
*/
register_program(Program, Id) :-
	prog_id(Program, Base),
	tagged_id(Base, Id),
	with_mutex(lps_http_sessions,
		   ( retractall(registered_program(Id, _)),
		     assertz(registered_program(Id, Program)) )).

session_of(Dict, Id, S) :-
	get_dict(session, Dict, IdS), atom_string(Id, IdS),
	(   with_mutex(lps_http_sessions, registered_session(Id, S, _))
	->  true
	;   throw(error(lps_no_such_session(Id), _))
	).

/*  Read-modify-write on one dynamic fact, from whichever HTTP worker took the
    request — so the same guard `lps_live.pl` puts on its own records, and for
    the same reason. Unguarded, `update_session/2` has a window between the
    retractall and the assertz in which the session does not exist, and a
    request landing in it is told `lps_no_such_session` for a session that is
    perfectly alive.

    Worth knowing how wide that window really is, because the answer surprised
    me. Four reader threads on eight cores never once hit it in 80,000 polls,
    which is how a bug like this stays theoretical. Twelve reader threads on the
    same eight cores hit it in 35% of 2.4 million polls: oversubscribe the CPU
    and the writer gets descheduled *inside* the window, which stops being
    nanoseconds and becomes a whole scheduler quantum. The deployment runs on
    `cpus = 1` with a worker pool, a live driver and an assistant job all
    contending, so it is the oversubscribed case that ships.
*/
register_session(S, Id) :-
	with_mutex(lps_http_sessions,
		   ( retract(session_counter_http(N)), N1 is N + 1,
		     assertz(session_counter_http(N1)) )),
	format(atom(Base), 's~w', [N1]),
	tagged_id(Base, Id),
	with_mutex(lps_http_sessions, assertz(registered_session(Id, S, 0))).

update_session(Id, S) :-
	with_mutex(lps_http_sessions,
		   ( retractall(registered_session(Id, _, _)),
		     assertz(registered_session(Id, S, 0)) )).

		 /*******************************
		 *	   conversions		*
		 *******************************/

source_terms(Source, Terms) :- source_terms(Source, Terms, _).

/* A program that does not parse is the *ordinary* state of a buffer being
   typed into, so a syntax error has to arrive as a diagnostic with a line and
   a column — something the editor can put a squiggle on — and not as a failed
   operation. Getting this wrong is how an editor comes to report "no errors"
   for a program that did not parse, which is the one thing it must never do.
*/
source_terms(Source, Terms, Diags) :-
	string(Source), !,
	catch(setup_call_cleanup(open_string(Source, In),
				 read_terms_in(In, Terms0),
				 close(In)),
	      E, true),
	(   var(E)
	->  Terms = Terms0, Diags = []
	;   Terms = [], syntax_diag(E, Diags)
	).
source_terms(Source, Terms, Diags) :-
	atom_string(A, Source), source_terms(A, Terms, Diags).

syntax_diag(error(syntax_error(What), Ctx), [D]) :- !,
	( syntax_position(Ctx, Line, Col) -> true ; Line = 1, Col = 0 ),
	format(atom(M), 'syntax error: ~w', [What]),
	diag(error, syntax_error, src(buffer, Line, Col, source), M, D).
syntax_diag(E, [D]) :-
	format(atom(M), '~q', [E]),
	diag(error, read_failed, src(buffer, 1, 0, source), M, D).

syntax_position(stream(_, Line, Col, _), Line, Col) :- integer(Line), !.
syntax_position(file(_, Line, Col, _), Line, Col) :- integer(Line), !.

%!	apply_provenance(+Dict, +Terms0, -Terms) is det.
%
%	Replace the line numbers read out of the internal text with the source
%	positions the *generator* of that text supplied. One entry per term,
%	matched on `index` (0-based, in term order); a term with no entry keeps
%	its own line. Documented in docs/dev/le-lps-interface.md, §3.
%
%	Positions are attached rather than merged so that a partial provenance
%	list — LE2 knows where twelve of a program's fifteen terms came from and
%	generated the other three — still places the twelve.
apply_provenance(Dict, Terms0, Terms) :-
	(   get_dict(provenance, Dict, Entries),
	    is_list(Entries)
	->  findall(I-S, ( member(E, Entries), provenance_entry(E, I, S) ), Pairs),
	    provenance_apply(Terms0, 0, Pairs, Terms)
	;   Terms = Terms0
	).

provenance_entry(E, Index, src(File, Line, Col, Kind)) :-
	is_dict(E),
	get_dict(index, E, Index), integer(Index),
	( get_dict(file, E, F) -> atom_string(File, F) ; File = le ),
	( get_dict(line, E, Line), integer(Line) -> true ; Line = 0 ),
	( get_dict(col, E, Col), integer(Col) -> true ; Col = 0 ),
	( get_dict(kind, E, K) -> atom_string(Kind, K) ; Kind = le ).

provenance_apply([], _, _, []).
provenance_apply([t(T, L0)|Ts], N, Pairs, [t(T, L)|Rest]) :-
	( memberchk(N-Src, Pairs) -> L = Src ; L = L0 ),
	N1 is N + 1,
	provenance_apply(Ts, N1, Pairs, Rest).

%	`module(lps_api)`, and it matters: a program's text is read with *this*
%	module's operator table, which is lps_ops.pl's — `actions`, `fluents`,
%	`initially`, `if`, `from`. It said `module(lps_http)` until the
%	operations moved here, which named a module that exists on a server and
%	not in the WebAssembly build, where SWI-Prolog then made an empty one:
%	every program failed to read at its first operator, reported as a
%	syntax error in the user's own file.
read_terms_in(In, Terms) :-
	line_count(In, L0), L is L0 + 1,
	read_term(In, T, [module(lps_api)]),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [t(T, L)|More], read_terms_in(In, More)
	).

%	Same reason as lps_live:parse_event/2: an unquoted `app.log` from a
%	client is an atom in every language but SWI-Prolog 7, where it is a
%	compound that prints identically and unifies with nothing.
parse_term_string(S, T) :-
	current_prolog_flag(allow_dot_in_atom, Old),
	setup_call_cleanup(
	    set_prolog_flag(allow_dot_in_atom, true),
	    term_string(T, S),
	    set_prolog_flag(allow_dot_in_atom, Old)).
term_string_(T, S) :- format(string(S), '~q', [T]).

%	`position` stays a printed term for the existing clients; `source` is
%	the same thing decomposed, which is what an editor needs to place a
%	marker (and, for an LE-sourced program, the only field that points at
%	something the author wrote).
diag_dict(diag(Sev, Code, Pos, Msg, _),
	  _{severity: SevS, code: CodeS, position: PosS, message: MsgS, source: SrcD}) :-
	format(string(SevS), '~w', [Sev]),
	format(string(CodeS), '~w', [Code]),
	format(string(PosS), '~w', [Pos]),
	format(string(MsgS), '~w', [Msg]),
	src_dict(Pos, SrcD).

src_dict(src(File, Line, Col, Kind), _{file: F, line: Line, col: Col, kind: K}) :- !,
	format(string(F), '~w', [File]),
	format(string(K), '~w', [Kind]).
src_dict(_, null).

/* What the editor needs to know about a program that is not a diagnostic.
 *
 * Four questions the IDE was guessing at or could not ask: which event terms
 * can this program receive (so the live panel's placeholder is one of *its*
 * events rather than `payment(alice, 100)`), does it declare any visual mapping
 * (so the 2D/3D buttons can be disabled with a reason instead of opening an
 * empty window), does it declare `maxTime` (so a live session can say that a
 * program which ends is an odd thing to run forever), and is it a planning
 * program. One reply, computed from the same compile the diagnostics came from.
 */
/*  `no/1` exists because `false` is an LPS *prefix operator* (`false A, B.`),
    so a bare `false` in an argument position is a syntax error in any file that
    imports lps_ops — which is every file here. Parenthesising it is the whole
    trick, and doing it once is better than doing it six times. */
no((false)).

truth(Goal, B) :- ( call(Goal) -> B = true ; no(B) ).

/*  The profile is also what the editor colours by. LPS1's SWISH gave fluent
    literals a pale blue chip and events an amber one
    (legacy_lps1/swish/web/lps/lps.css), and it could only do that because it
    knew which was which — a syntax highlighter cannot tell `loc(wolf,north)`
    from `row(south,north)` by looking. So the declarations come back here, and
    the editor decorates the names it finds. */
program_profile(P, _{events: E, actions: A, fluents: F, display: D2,
		     display3d: D3, max_time: MT, planning: Pl}) :-
	(   P == none
	->  E = [], A = [], F = [], no(D2), no(D3), MT = null, no(Pl)
	;   profile_terms(P, p_user_event, E),
	    profile_terms(P, p_user_action, A),
	    profile_terms(P, p_user_fluent_decl, F),
	    truth(has_clauses(P, display, 2), D2),
	    truth(has_clauses(P, display3d, 2), D3),
	    ( prog_setting(P, maxTime, MT0), number(MT0) -> MT = MT0 ; MT = null ),
	    truth(( prog_module(P, M), catch(M:achieve(_), _, fail) ), Pl)
	).

%	Templates, printed as a person would type them: `temperature(_)`, not
%	`temperature(_G14014)`. The declaration *is* a template, so its variables
%	are holes rather than names.
profile_terms(P, Which, Strings) :-
	Goal =.. [Which, P, T],
	findall(S, ( catch(call(lps_program:Goal), _, fail),
		     \+ functor(T, lps_terminate, _),
		     template_string(T, S) ), Ss),
	sort(Ss, Strings).

template_string(T0, S) :-
	copy_term(T0, T),
	term_variables(T, Vs),
	maplist(=('$VAR'('_')), Vs),
	format(string(S), '~W', [T, [quoted(true), numbervars(true)]]).

has_clauses(P, Name, Arity) :-
	prog_module(P, M),
	functor(Head, Name, Arity),
	catch(( current_predicate(M:Name/Arity),
		\+ predicate_property(M:Head, imported_from(_)),
		clause(M:Head, _) ), _, fail).

report_dict(cycle(Time, Events, Composites, Fluents, Actions),
	    _{time: Time, events: E, composites: C, fluents: F, actions: A}) :-
	maplist(term_string_, Events, E),
	maplist(term_string_, Composites, C),
	maplist(term_string_, Fluents, F),
	maplist(term_string_, Actions, A).

node_dict(node(Label, Detail, Kids), _{label: L, detail: D, children: KD}) :-
	format(string(L), '~w', [Label]),
	format(string(D), '~w', [Detail]),
	maplist(node_dict, Kids, KD).

%	A fluent with no key has one value: its default says something only
%	when, at some cycle, no value of it is stored.
scalar_always_stored(D, Lanes, Max) :-
	functor(D, F, 1),
	forall(between(0, Max, C),
	       ( member(lane(Fl, Ivs), Lanes), functor(Fl, F, 1),
		 member(interval(A, B), Ivs), C >= A, C =< B )).

%	`balance(_, 0)` as `balance(…, 0)`: the keys are any key.
default_string(D, S) :-
	D =.. [F|As], append(Ks, [V], As),
	maplist(=('…'), Ks), D1 =.. [F|Ks], ( Ks == [] -> KT = F ; format(atom(KT), '~w', [D1]) ),
	(   Ks == [] -> format(string(S), '~w(~q)', [F, V])
	;   sub_atom(KT, 0, _, 1, Open), format(string(S), '~w, ~q)', [Open, V])
	).

fluent_lane_dict(lane(F, Intervals), _{fluent: FS, intervals: IS}) :-
	term_string_(F, FS),
	maplist([interval(A, B), _{from: A, to: B}]>>true, Intervals, IS).

stage_lane_dict(lane(_, Cells), CD) :-
	maplist(cell_dict, Cells, CD).

cell_dict(cell(C, Items), _{cycle: C, items: IS}) :- maplist(term_string_, Items, IS).

%	One frame of the strip: the scene at that cycle, and the words for what
%	got the run there.
scene_frame(S, Decl, kf(C, StateId, Events), Frame) :-
	lps_session_scene(S, C, Decl, scene(_, Timeless0, Items)),
	scene_objects(Timeless0, Timeless),
	maplist(props_dict, Timeless, TL),
	maplist(visual_dict, Items, IV),
	maplist(term_string_, Events, ES),
	(   catch(lps_session_changes(S, C, changes(_, I, T, U, _)), _, fail)
	->  maplist(changed_fluent, I, Began),
	    maplist(changed_fluent, T, Ended),
	    maplist(changed_fluent, U, Updated)
	;   Began = [], Ended = [], Updated = []
	),
	( StateId = [_, _|_] -> Returns = true ; Returns = false ),
	Frame = _{cycle: C, events: ES, began: Began, ended: Ended,
		  updated: Updated, returns: Returns, state: StateId,
		  timeless: TL, items: IV}.

changed_fluent(change(F, _, _, _), S) :- term_string_(F, S).

change_dict(change(F, A, Src, _), _{fluent: FS, action: AS, source: SS}) :-
	term_string_(F, FS), term_string_(A, AS), format(string(SS), '~w', [Src]).

%	A node's identity is its list of cycles — that is what makes two visits
%	to the same state one state — so it travels as a string the front end
%	can use as a key without having to re-derive it.
disc_dict(disc(Name/Arity, Example, Instances, Kind),
	  _{fluent: FS, name: NS, arity: Arity, example: ES,
	    instances: Instances, kind: KS}) :-
	format(string(FS), '~w/~w', [Name, Arity]),
	format(string(NS), '~w', [Name]),
	term_string_(Example, ES),
	format(string(KS), '~w', [Kind]).

keyframe_dict(kf(Cycle, StateId, Events),
	      _{cycle: Cycle, state: StateId, events: ES, returns: Returns}) :-
	maplist(term_string_, Events, ES),
	( StateId = [_, _|_] -> Returns = true ; Returns = false ).

automaton_node_dict(node(Id, Fluents, Cycles, Initial),
		    _{id: IdS, fluents: FS, cycles: Cycles, initial: Initial}) :-
	term_string_(Id, IdS),
	maplist(term_string_, Fluents, FS).

automaton_edge_dict(edge(From, To, Label, Kind),
		    _{from: FS, to: TS, label: LS, kind: KS}) :-
	term_string_(From, FS), term_string_(To, TS),
	term_string_(Label, LS),
	format(string(KS), '~w', [Kind]).

%	Visual properties come across as {key: value} with values stringified:
%	the front end needs `point:[75,120]` as numbers where it can get them,
%	so lists of numbers are passed through rather than printed.
props_dict(Props, Dict) :-
	findall(K-V, ( member(Prop, Props), prop_pair(Prop, K, V) ), Pairs),
	dict_pairs(Dict, props, Pairs).

/* `display(timeless, Spec)` may be a list of objects *or* a single flat
   property list — 2dWord.md allows both, and bubbleSort.pl uses the flat form.
   Mapping over the flat one produced an object per property, i.e. nothing.
*/
scene_objects(Spec, Objects) :-
	(   Spec = [First|_], is_list(First)
	->  Objects = Spec
	;   Spec == []
	->  Objects = []
	;   Objects = [Spec]
	).

prop_pair(K:V, K, Out) :- !, prop_value(V, Out).
prop_pair(Atom, Atom, true) :- atom(Atom).

prop_value(V, V) :- number(V), !.
prop_value(V, Out) :- is_list(V), !, maplist(prop_value, V, Out).
prop_value(V, Out) :- format(string(Out), '~w', [V]).

/*  A COMPOSITE event's subject is the engine's own record of the act —
    `happens(journey(finish), 1, 3)` — because that is what carries the
    interval the picture draws it over. What a reader wants to ask about is the
    act itself, at the cycle it ended, so the dict carries that separately:
    `ask` and `at`. Without them a right-click on a span asked
    `why(happened(happens(journey(finish),1,3)), 5)`, which is not a question.
*/
visual_dict(visual(composite, happens(E, Start, End), Props),
	    _{kind: "composite", subject: S, ask: A, at: End, props: P}) :- !,
	term_string_(happens(E, Start, End), S),
	term_string_(E, A),
	props_dict(Props, P).
visual_dict(visual(Kind, Subject, Props), _{kind: K, subject: S, props: P}) :-
	format(string(K), '~w', [Kind]),
	term_string_(Subject, S),
	props_dict(Props, P).

stage_dict(Stage, Cycle, Items, _{stage: S, cycle: Cycle, items: I}) :-
	format(string(S), '~w', [Stage]),
	maplist(term_string_, Items, I).
