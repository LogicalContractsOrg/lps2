/* lps_le.pl — the Logical English edge (§I.9, M8a).

   LPS2 does not parse Logical English. LE2 does, and it owns the template
   dictionary, so it owns the only mapping that can be inverted (§I.9.5). What
   crosses the boundary is *LPS internal syntax as text*, plus a provenance
   list that points each generated term back at the `.le` sentence it came
   from. The contract is docs/le_lps_interface.md, which is duplicated verbatim
   in the LE2 repository.

   Three transports, all explicit, none guessed:

     LPS_LE2_LIB   a checkout of the LE2 repository, whose `le_service.pl` is
		   loaded **into this image**. Preferred when set: translating
		   is then a predicate call, which is what makes editing
		   Logical English here practical — a keystroke's worth of
		   latency rather than a process start. §3.5 of the interface.
     LPS_LE2_URL   an HTTP endpoint speaking LE2's `/leapi` protocol. The
		   deployment case: two servers, no proxy
		   (docs/le_lps_design.md §3).
     LPS_LE2_DIR   a checkout, run as a *subprocess*. The isolated case: one
		   document's `halt/0` cannot take the caller with it.

   With none set, `./lps run foo.le` refuses and says which variable to set.
   It must not silently guess: a `.le` file compiled by the wrong LE2 is a
   program whose meaning nobody stated.

   **LE2 is optional.** Nothing here is loaded at build time and nothing else
   in LPS2 references it: with no LE2 present the engine, the IDE, the CLI and
   every gate work exactly as they do now, and the only thing that stops
   working is Logical English. That is why the library is loaded with
   `load_files/2` inside a catch at the moment it is first needed, rather than
   with a `use_module` directive — a directive would make a missing LE2 a
   *load* error for this file, and this file is on the CLI's path.
*/

:- module(lps_le, [
	lps_le_translate/4,      % +File, -InternalText, -Provenance, -Diags
	lps_le_translate_text/5, % +Text, +Name, -InternalText, -Provenance, -Diags
	lps_le_available/1,      % -How  (lib(D) | url(U) | dir(D) | none)
	lps_le_library/1,        % -Dir   the loaded in-process LE2, if any
	lps_le_call/1,           % :Goal  run a goal in the loaded LE2
	lps_le_service_version/1,% -Version
	%  The companion-file rule (docs/le_lps_surface.md §7), for buffers
	lps_le_program_terms/7,  % +Text, +Name, +Prov, +Companion, +CName, -Terms, -Diags
	lps_le_templates/3,      % +Source, +Name, -Templates   (in-process only)
	lps2_root/1,             % -Dir   the repository root
	lps_le_companion_terms/4,% +Source, +Name, -Terms, -Diags
	lps_le_companion_name/2, % +LEName, -CompanionName
	lps_le_resolve_resource/4% +Name, +Source, +Resource, -Where
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(process)).
:- use_module(library(http/json)).
:- use_module(library(http/http_open)).
:- use_module('../core/lps_diag').
:- use_module('../syntax/lps_legacy_syntax').
:- use_module(lps_source).

%!	lps_le_available(-How) is det.
%
%	How the LE layer is reachable: `lib(D)`, `url(U)`, `dir(D)`, or `none`.
%	The order is deliberate — in-process first, because it is the one that
%	makes an editor possible.
lps_le_available(How) :-
	%  A directory *with a le_service.pl in it*: the image always has a
	%  vendor/le2 path configured, and an image built without the vendoring
	%  step has an empty one. "Configured but empty" must read as "no LE2",
	%  not as "LE2 that fails on every call".
	(   getenv('LPS_LE2_LIB', L), L \== '', le_checkout_dir(L)
	->  How = lib(L)
	;   getenv('LPS_LE2_URL', U), U \== ''
	->  How = url(U)
	;   getenv('LPS_LE2_DIR', D), D \== '', le_checkout_dir(D)
	->  /*  A checkout is loaded in-process *by default*. The subprocess was
	        the original answer to "a .le document can pull in arbitrary
	        Prolog", and it is still the right answer when isolation is worth
	        a process start — but the hazard it guards against is already
	        handled inside LE2, whose resource loader asserts rather than
	        consults. Set LPS_LE2_SUBPROCESS to have it back.  */
	    ( subprocess_wanted -> How = dir(D) ; How = lib(D) )
	;   How = none
	).

le_checkout_dir(D) :-
	exists_directory(D),
	atomic_list_concat([D, '/le_service.pl'], F),
	exists_file(F).

subprocess_wanted :-
	getenv('LPS_LE2_SUBPROCESS', V), V \== '', V \== '0', V \== 'false'.

		 /*******************************
		 *	 the in-process one	*
		 *******************************/

:- dynamic le_lib_loaded/1.       % Dir
:- dynamic le_lib_failed/2.       % Dir, Message

%!	lps_le_library(-Dir) is semidet.
%
%	The LE2 checkout loaded into this image, if one is. Succeeds only after
%	a successful load, so a caller can test for the editor-facing
%	predicates without provoking one.
lps_le_library(Dir) :- le_lib_loaded(Dir).

%!	lps_le_load(+Dir, -Error) is det.
%
%	Load `Dir/le_service.pl` once. Error is `ok` or a message.
%
%	Two checkouts in one image is refused rather than resolved: LE2's
%	modules are named `le_*` and loading a second copy would either be a
%	no-op (silently answering with the first) or a redefinition. Saying so
%	is the only honest answer.
lps_le_load(Dir, ok) :- le_lib_loaded(Dir), !.
lps_le_load(Dir, Error) :-
	le_lib_loaded(Other), Other \== Dir, !,
	format(atom(Error),
	       'LE2 is already loaded from ~w; one image cannot hold two \c
		checkouts. Restart with LPS_LE2_LIB=~w.', [Other, Dir]).
lps_le_load(Dir, Error) :- le_lib_failed(Dir, Error), !.
lps_le_load(Dir, Error) :-
	atomic_list_concat([Dir, '/le_service.pl'], File),
	(   \+ exists_file(File)
	->  format(atom(Error),
		   '~w is not an LE2 checkout: no le_service.pl in it. That file \c
		    is LE2\'s embedding surface and it is what LPS_LE2_LIB must \c
		    point at the directory of.', [Dir]),
	    assertz(le_lib_failed(Dir, Error))
	;   catch(( load_le_quietly(File), Loaded = true ), E,
		  ( message_to_text(E, M),
		    format(atom(Error0), 'could not load ~w: ~w', [File, M]),
		    Loaded = false )),
	    (   Loaded == true
	    ->  Error = ok, assertz(le_lib_loaded(Dir)), configure_le
	    
	    ;   Error = Error0, assertz(le_lib_failed(Dir, Error0))
	    )
	).

/*  Two things to say to a freshly loaded LE2, both of them about being *in*
    somebody else's process rather than being the process:

    - its issues come back to us as data, so printing them as well puts a
      second copy on our stderr, interleaved and out of order on a threaded
      server;
    - a document may name a resource by URL, and an editor that fetched it
      would be making an outbound request on the author's behalf, from our
      server, because they opened a file. `LPS_LE2_NETWORK=1` allows it for
      somebody who means it.  */
configure_le :-
	catch(le_service:set_le_issue_reporting(false), _, true),
	%  English→LE goes through *our* LLM client, so it uses the keys the
	%  server was started with and the model the IDE's picker chose. Two
	%  clients in one image would be two registries and two answers to
	%  "which model is this".
	catch(le_service:set_le_llm_provider(lps_llm), _, true),
	(   getenv('LPS_LE2_NETWORK', N), N \== '', N \== '0', N \== 'false'
	->  catch(le_service:set_le_network_allowed(true), _, true)
	;   catch(le_service:set_le_network_allowed(false), _, true)
	).

%	LE2 prints load-time warnings that are not this program's diagnostics —
%	singleton variables in its own sources, mostly — and they would arrive
%	interleaved with ours. The load itself is not silenced: an *error* still
%	throws, and that is what the catch above is for.
load_le_quietly(File) :-
	setup_call_cleanup(
	    ( current_prolog_flag(verbose, V0), set_prolog_flag(verbose, silent) ),
	    load_files(File, [if(not_loaded), silent(true)]),
	    set_prolog_flag(verbose, V0)).

message_to_text(E, Text) :-
	(   catch(message_to_codes_(E, Text), _, fail) -> true
	;   format(atom(Text), '~q', [E])
	).

message_to_codes_(E, Text) :-
	message_to_text_lines(E, Lines),
	atomic_list_concat(Lines, ' ', Text).

message_to_text_lines(E, [Text]) :-
	format(atom(Text), '~q', [E]).

%!	lps_le_call(:Goal) is semidet.
%
%	Call Goal in the loaded LE2, or fail if there is none. Every use of an
%	LE2 predicate goes through here, so "LE2 is not loaded" is one branch
%	rather than a scattered `current_predicate/1` in every caller.
lps_le_call(Goal) :-
	lps_le_ensure(ok),
	catch(call(Goal), E, ( print_message(warning, E), fail )).

%!	lps_le_ensure(-Status) is det.
%
%	`ok` when LE2 is loaded here, having loaded it if `LPS_LE2_LIB` names a
%	checkout and this is the first call; otherwise a message saying why not.
%	The load is lazy on purpose: a session that never opens a `.le` file
%	should not pay 1.5 s and 10 MB for the possibility.
lps_le_ensure(ok) :- le_lib_loaded(_), !.
lps_le_ensure(Status) :-
	(   lps_le_available(lib(Dir))
	->  lps_le_load(Dir, Status)
	;   Status = 'Logical English is not loaded in this process: set \c
		      LPS_LE2_LIB to an LE2 checkout.'
	).

%!	lps_le_service_version(-Version) is semidet.
lps_le_service_version(V) :-
	lps_le_call(le_service:le_service_version(V)).

%!	lps_le_translate(+File, -Text, -Provenance, -Diags) is det.
%
%	Text is LPS internal syntax; Provenance is a list of
%	`prov(Index, File, Line, Col, Kind)` in term order, ready to be zipped
%	onto the terms read out of Text; Diags are LE-side diagnostics already
%	in `diag/5` shape. On any failure Text is the empty string and Diags
%	carries one error — never a partial program.
lps_le_translate(File, Text, Provenance, Diags) :-
	lps_le_available(How),
	lps_le_translate_(How, File, Text, Provenance, Diags).

%!	lps_le_translate_text(+Source, +Name, -Text, -Provenance, -Diags) is det.
%
%	The same, for a buffer rather than a file — which is what an editor
%	has. Only the in-process and HTTP transports can do it; the subprocess
%	one needs a path, so the text is written to a temporary file for it.
lps_le_translate_text(Source, Name, Text, Provenance, Diags) :-
	lps_le_available(How),
	lps_le_translate_text_(How, Source, Name, Text, Provenance, Diags).

lps_le_translate_text_(none, _, Name, "", [], [D]) :- !,
	not_configured(Name, D).
lps_le_translate_text_(lib(Dir), Source, Name, Text, Provenance, Diags) :- !,
	le_lib_payload(Dir, Source, Name, Text, Provenance, Diags).
lps_le_translate_text_(url(U), Source, Name, Text, Provenance, Diags) :- !,
	(   catch(le_post(U, Source, Reply), E, (le_error(E, D2), Reply = none))
	->  (   Reply == none
	    ->	Text = "", Provenance = [], Diags = [D2]
	    ;	le_reply(Reply, Name, Text, Provenance, Diags)
	    )
	;   Text = "", Provenance = [],
	    format(atom(M), 'LE2 endpoint ~w did not answer', [U]),
	    diag(error, le_endpoint_failed, unknown, M, D), Diags = [D]
	).
lps_le_translate_text_(dir(Dir), Source, Name, Text, Provenance, Diags) :-
	setup_call_cleanup(
	    tmp_le_file(Source, Tmp),
	    lps_le_translate_(dir(Dir), Tmp, Text, Provenance, Diags0),
	    catch(delete_file(Tmp), _, true)),
	%  The diagnostics point at the temporary file; the caller means the
	%  buffer.
	maplist(rename_source(Name), Diags0, Diags).

tmp_le_file(Source, File) :-
	tmp_file_stream(text, Base, Out), close(Out),
	atom_concat(Base, '.le', File),
	setup_call_cleanup(open(File, write, S, [encoding(utf8)]),
			   write(S, Source), close(S)),
	catch(delete_file(Base), _, true).

rename_source(Name, diag(S, C, src(_, L, Col, K), M, X), diag(S, C, src(Name, L, Col, K), M, X)) :- !.
rename_source(_, D, D).

lps_le_translate_(none, File, "", [], [D]) :-
	not_configured(File, D).
lps_le_translate_(lib(Dir), File, Text, Provenance, Diags) :-
	(   catch(read_file_to_string(File, Source, [encoding(utf8)]), _, fail)
	->  le_lib_payload(Dir, Source, File, Text, Provenance, Diags)
	;   Text = "", Provenance = [],
	    format(atom(M), 'cannot read ~w', [File]),
	    diag(error, read_failed, unknown, M, D), Diags = [D]
	).

lps_le_translate_(url(U), File, Text, Provenance, Diags) :-
	(   catch(read_file_to_string(File, Source, [encoding(utf8)]), E1, (E1 = _, fail))
	->  (   catch(le_post(U, Source, Reply), E2, (le_error(E2, D2), Reply = none))
	    ->	(   Reply == none
		->  Text = "", Provenance = [], Diags = [D2]
		;   le_reply(Reply, File, Text, Provenance, Diags)
		)
	    ;	Text = "", Provenance = [],
		format(atom(M), 'LE2 endpoint ~w did not answer', [U]),
		diag(error, le_endpoint_failed, unknown, M, D), Diags = [D]
	    )
	;   Text = "", Provenance = [],
	    format(atom(M), 'cannot read ~w', [File]),
	    diag(error, read_failed, unknown, M, D), Diags = [D]
	).
lps_le_translate_(dir(Dir), File, Text, Provenance, Diags) :-
	absolute_file_name(File, Abs),
	format(atom(Goal),
	       "use_module(le_lps), le_lps:le_lps_json('~w')", [Abs]),
	(   catch(run_le2(Dir, Goal, Out), E, (le_error(E, D0), Out = none))
	->  (   Out == none
	    ->	Text = "", Provenance = [], Diags = [D0]
	    ;	(   catch(atom_json_dict(Out, Reply, []), _, fail)
		->  le_reply(Reply, File, Text, Provenance, Diags)
		;   Text = "", Provenance = [],
		    format(atom(M), 'LE2 in ~w produced no JSON (got: ~w)', [Dir, Out]),
		    diag(error, le_bad_reply, unknown, M, D), Diags = [D]
		)
	    )
	;   Text = "", Provenance = [],
	    format(atom(M), 'could not run LE2 in ~w', [Dir]),
	    diag(error, le_run_failed, unknown, M, D), Diags = [D]
	).

not_configured(File, D) :-
	format(atom(M),
	       'cannot compile ~w: Logical English is parsed by LE2, which is not \c
		configured. Set LPS_LE2_LIB to an LE2 checkout to load it into \c
		this process, LPS_LE2_URL to an LE2 /leapi endpoint, or \c
		LPS_LE2_DIR to run it as a subprocess.', [File]),
	diag(error, le_not_configured, unknown, M, D).

		 /*******************************
		 *	 the companion file	*
		 *******************************/

/*  `foo.le` and `foo.lps` compile together, `.le` first.
 *
 *  That is the documented escape hatch of docs/le_lps_surface.md §7: a
 *  `display/2` clause, a Prolog escape and the real-time plumbing are not
 *  Logical English and gain nothing from being written as if they were, so
 *  they go in a companion file with the right editor mode and the right
 *  diagnostics rather than in an in-band block the LE editor cannot check.
 *
 *  `lps_cli.pl` has the same rule for *files*, where the companion is found on
 *  disk beside the document. These are the same rule for *buffers*, which is
 *  what an editor and the assistant hold: nothing is on disk, so the caller
 *  says what the companion is and this says what it means. The IDE went
 *  without them for a while, and the consequence was not that a `.le` document
 *  merely lost its picture — the 2D pane, seeing no `display/2`, offered to
 *  write some, and the assistant wrote Prolog into the English.
 */

%!	lps_le_companion_name(+Name, -Companion) is det.
%
%	`badlight.le` → `badlight.lps`. Anything else keeps its name with `.lps`
%	appended, which is what an unsaved buffer called `untitled` should get.
lps_le_companion_name(Name, Companion) :-
	atom_string(A, Name),
	(   file_name_extension(Base, le, A)
	->  true
	;   Base = A
	),
	file_name_extension(Base, lps, Companion).

%!	lps_le_companion_terms(+Source, +Name, -Terms, -Diags) is det.
%
%	The companion half, as text: LPS external syntax in, internal terms out.
%	Every term carries Name as a full source position, so that a diagnostic
%	about the companion is reported against the *companion* — an editor
%	showing both files has to know which one to put the squiggle in, and a
%	bare line number would put a companion's error on that line of the
%	English.
lps_le_companion_terms(Source, Name, Terms, Diags) :-
	lps_read_terms_string(Source, Name, Raw, ReadDiags),
	(   ReadDiags == []
	->  legacy_to_internal(terms(Raw), [origin(Name)], Terms0, Diags),
	    maplist(companion_src(Name), Terms0, Terms)
	;   Terms = [], Diags = ReadDiags
	).

companion_src(Name, t(T, Line), t(T, src(Name, Line, 0, legacy))) :- integer(Line), !.
companion_src(_, T, T).

%!	lps_le_program_terms(+Text, +Name, +Prov, +Companion, +CName,
%!			     -Terms, -Diags) is det.
%
%	Everything a Logical English program is made of: the terms LE2 generated
%	— each positioned back onto the sentence it came from, which is what the
%	provenance array is for (docs/le_lps_interface.md §3) — followed by the
%	companion's, if there is one. Ready for `lps_compile(terms(Terms),
%	internal, …)`.
%
%	Companion is the empty string (or the empty atom) when there is none,
%	which is the ordinary case: fifteen of LE2's seventeen LPS examples have
%	no companion at all.
lps_le_program_terms(Text, Name, Prov, Companion, CName, Terms, Diags) :-
	lps_read_terms_string(Text, Name, Terms0, ReadDiags),
	lps_le_prov_terms(Prov, Terms0, Terms1),
	(   has_companion(Companion)
	->  lps_le_companion_terms(Companion, CName, CTerms, CDiags)
	;   CTerms = [], CDiags = []
	),
	append(Terms1, CTerms, Terms),
	append(ReadDiags, CDiags, Diags).

has_companion(C) :- nonvar(C), C \== "", C \== '', C \== null.

%	Zip the provenance onto the terms read out of the generated text.
lps_le_prov_terms(Prov, Terms0, Terms) :-
	findall(I-src(F, L, C, K), member(prov(I, F, L, C, K), Prov), Pairs),
	prov_apply(Terms0, 0, Pairs, Terms).

prov_apply([], _, _, []).
prov_apply([t(T, L0)|Ts], N, Pairs, [t(T, L)|Rest]) :-
	( memberchk(N-Src, Pairs) -> L = Src ; L = L0 ),
	N1 is N + 1,
	prov_apply(Ts, N1, Pairs, Rest).

/*  The in-process payload.

    It goes through `le_lps_dict/4` and then through the *same* `le_reply/5`
    the other two transports use, rather than shaping `le_lps_text/4`'s terms
    directly. One extra dict per call buys the property the gate checks: the
    three transports cannot drift, because two thirds of the path is literally
    shared and the third is a dict LE2 itself built.  */
le_lib_payload(Dir, Source, Name, Text, Provenance, Diags) :-
	lps_le_load(Dir, Load),
	(   Load \== ok
	->  Text = "", Provenance = [],
	    diag(error, le_lib_failed, unknown, Load, D), Diags = [D]
	;   catch(le_lib_dict(Source, Name, Reply), E, (le_error(E, D1), Reply = none))
	->  (   Reply == none
	    ->	Text = "", Provenance = [], Diags = [D1]
	    ;	le_reply(Reply, Name, Text, Provenance, Diags)
	    )
	;   Text = "", Provenance = [],
	    diag(error, le_lib_failed, unknown,
		 'LE2 is loaded but did not translate the document', D),
	    Diags = [D]
	).

%	When Name is a file that exists, its directory is handed to LE2 as the
%	base for `includes these resources:` lines — otherwise LE2 resolves a
%	relative resource against the working directory, and `./lps run
%	examples/if/story.le` from the repository root cannot find the
%	library beside the story. A buffer with no file keeps the old path.
le_lib_dict(Source, Name, Reply) :-
	(   include_base(Name, Source, Base),
	    lps_le_call(le_service:le_kb_of_text(Source, [base(Base)], KB))
	->  lps_le_call(le_service:le_lps_module(KB, Source, T0, P, I)),
	    empty_template_directives(KB, Source, T0, T)
	;   lps_le_call(le_service:le_lps_text(Source, T, P, I))
	),
	lps_le_call(le_service:le_lps_dict(T, P, I, Reply)).

%!	lps_le_templates(+Source, +Name, -Templates) is det.
%
%	The templates of a document, as LE2's `le_template(F/A, Role, Surface,
%	Slots, Position, Flags)` terms — what a parser and a narrator need
%	(src/edges/lps_play.pl). In-process only: the other transports have
%	no knowledge base to ask, and return `[]`. Name, when it is a file,
%	fixes the base for includes as in le_lib_dict/3.
lps_le_templates(Source, Name, Templates) :-
	(   lps_le_available(lib(_)),
	    ( include_base(Name, Source, Base) -> Opts = [base(Base)] ; Opts = [] ),
	    lps_le_call(le_service:le_kb_of_text(Source, Opts, KB)),
	    lps_le_call(le_service:le_templates(KB, Source, Ts0))
	->  %  Under `; known as f` the program's predicate is `f`, not LE2's
	    %  derived name, and the program's is the one a consumer of LPS
	    %  terms needs — so the functor comes back renamed, as the emitter
	    %  renames it (le_lps:lps_functor/3).
	    maplist(known_as_functor(KB), Ts0, Templates)
	;   Templates = []
	).

known_as_functor(KB, le_template(F0/A, R, S, Sl, P, Fl), le_template(F/A, R, S, Sl, P, Fl)) :-
	(   catch(KB:le_lps_functor(F0/A, F1), _, fail)
	->  F = F1
	;   F = F0
	).

%!	include_base(+Name, -Base) is semidet.
%
%	The directory a document's relative includes resolve against: the
%	directory of the file Name names — as given, or under this
%	repository's `examples/`, which is how the IDE names a tab it opened
%	from the examples browser (`if/doors.le`). A buffer with no file has
%	no base and LE2 falls back to the working directory.
include_base(Name, Source, Base) :-
	(   include_base(Name, Base)
	->  true
	;   %  A document with no file of its own — a story generated from an
	    %  Inform source, or typed into a fresh tab — that includes the
	    %  interactive-fiction library resolves against the library's home.
	    sub_string(Source, _, _, _, "includes these resources: world"),
	    lps2_root(Root), atomic_list_concat([Root, '/examples/if'], Base)
	).

%!	lps_le_resolve_resource(+Name, +Source, +Resource, -Where) is det.
%
%	Where an item of a document's `includes these resources:` line points,
%	by LE2's own rule (le_kbs.pl: a URL as it is; else relative to the
%	including file's directory, `.pl` kept and `.le` implied) from the
%	same base the compiler resolves the include against (include_base/3,
%	so a tab named `doors.le` finds `examples/if/`). Where is `url(URL)`,
%	`file(Path)` for a file that exists, `missing(Path)` for one that does
%	not, or `outside(Path)` for a file the server will not hand out: only
%	files under this repository are served, as the examples are.
lps_le_resolve_resource(Name, Source, Resource0, Where) :-
	normalize_space(atom(Resource), Resource0),
	(   ( sub_atom(Resource, 0, _, _, 'http://') ; sub_atom(Resource, 0, _, _, 'https://') )
	->  Where = url(Resource)
	;   ( include_base(Name, Source, Base) -> true ; working_directory(Base, Base) ),
	    atom_concat(Base, '/', BaseDir),
	    absolute_file_name(Resource, Full0, [relative_to(BaseDir)]),
	    ( sub_atom(Full0, _, 3, 0, '.pl') -> Full = Full0 ; atom_concat(Full0, '.le', Full) ),
	    lps2_root(Root), atom_concat(Root, '/', RootDir),
	    (   \+ sub_atom(Full, 0, _, _, RootDir)
	    ->  Where = outside(Full)
	    ;   exists_file(Full)
	    ->  Where = file(Full)
	    ;   Where = missing(Full)
	    )
	).

include_base(Name, Base) :-
	atom(Name), Name \== '',
	lps2_root(Root),
	(   member(Cand, [Name, Root/examples/Name, Root/Name]),
	    ( Cand = A/B/C -> atomic_list_concat([A, '/', B, '/', C], File)
	    ; Cand = A/B -> atomic_list_concat([A, '/', B], File)
	    ; File = Cand ),
	    catch(exists_file(File), _, fail)
	->  true
	;   %  The IDE names a tab by its basename (`doors.le`), so the
	    %  document is looked for one level down in `examples/`.
	    file_base_name(Name, Basename),
	    atomic_list_concat([Root, '/examples/*/', Basename], Pattern),
	    expand_file_name(Pattern, [File|_]),
	    exists_file(File)
	->  true
	;   %  A document File ▸ Open converted from another system's file:
	    %  its translator wrote it, and what it includes, under
	    %  build/imports/<id>/out/ — the latest such conversion is the tab's.
	    file_base_name(Name, Basename),
	    atomic_list_concat([Root, '/build/imports/*/out/', Basename], Pattern),
	    expand_file_name(Pattern, Files), Files \== [],
	    findall(T-F, ( member(F, Files), time_file(F, T) ), TFs),
	    max_member(_-File, TFs)
	), !,
	absolute_file_name(File, Abs), file_directory_name(Abs, Base).

lps2_root(Root) :-
	module_property(lps_le, file(F)),
	file_directory_name(F, Edges), file_directory_name(Edges, Src),
	file_directory_name(Src, Root).

%!	empty_template_directives(+KB, +Source, +Text0, -Text) is det.
%
%	A timeless template the document declares but states nothing for —
%	`*a door* leads *a direction* from *a room* to *a second room*` in a
%	story with no doors — is a predicate with no clauses, and the engine
%	raises an existence error the first time a rule asks about it. In
%	Logical English a declared template with no facts is simply false, so
%	each such template is declared `:- dynamic`, which the program builder
%	honours (lps_program:apply_directives/4). The directives are appended
%	to the internal text, after every provenance index, so the provenance
%	list is untouched.
empty_template_directives(KB, Source, T0, T) :-
	(   catch(le_service:le_templates(KB, Source, Ts), _, fail)
	->  findall(F/A,
		    ( member(le_template(F/A, predicate, _, _, Pos, _), Ts),
		      Pos = pos(Start, _, _, _), integer(Start), Start >= 0,
		      functor(Head, F, A),
		      \+ catch(clause(KB:Head, _), _, fail) ),
		    FAs0),
	    sort(FAs0, FAs)
	;   FAs = []
	),
	(   FAs == []
	->  T = T0
	;   with_output_to(string(Extra),
			   forall(member(F/A, FAs),
				  format(':- dynamic ~q/~w.~n', [F, A]))),
	    string_concat(T0, Extra, T1),
	    string_concat(T1, "\n", T)
	).

le_error(E, D) :-
	format(atom(M), 'Logical English translation failed: ~q', [E]),
	diag(error, le_failed, unknown, M, D).

%	The reply shape both transports share (docs/le_lps_interface.md §2).
le_reply(Reply, File, Text, Provenance, Diags) :-
	( get_dict(lps, Reply, T) -> Text = T ; Text = "" ),
	( get_dict(provenance, Reply, P), is_list(P) -> P1 = P ; P1 = [] ),
	findall(prov(I, F, L, C, K),
		( member(E, P1), prov_entry(E, File, I, F, L, C, K) ),
		Provenance),
	( get_dict(issues, Reply, Is), is_list(Is) -> Is1 = Is ; Is1 = [] ),
	findall(D, ( member(I0, Is1), issue_diag(I0, File, D) ), Diags).

prov_entry(E, Default, Index, F, Line, Col, Kind) :-
	is_dict(E),
	get_dict(index, E, Index), integer(Index),
	( get_dict(file, E, F0) -> atom_string(F, F0) ; F = Default ),
	( get_dict(line, E, Line), integer(Line) -> true ; Line = 0 ),
	( get_dict(col, E, Col), integer(Col) -> true ; Col = 0 ),
	( get_dict(kind, E, K0) -> atom_string(Kind, K0) ; Kind = le ).

issue_diag(I, File, D) :-
	is_dict(I),
	( get_dict(severity, I, S0), atom_string(S1, S0), memberchk(S1, [error, warning, info])
	-> S = S1 ; S = error ),
	( get_dict(type, I, T0) -> atom_string(Code, T0) ; Code = le_issue ),
	( get_dict(message, I, M0) -> atom_string(Msg, M0) ; Msg = '' ),
	( get_dict(line, I, L), integer(L) -> true ; L = 0 ),
	( get_dict(col, I, C), integer(C) -> true ; C = 0 ),
	diag(S, Code, src(File, L, C, le), Msg, D).

le_post(URL, Source, Reply) :-
	atom_json_dict(Body, _{operation: "getLps", le: Source}, [as(atom)]),
	setup_call_cleanup(
	    http_open(URL, In, [ method(post), post(atom('application/json', Body)),
				 request_header('Content-Type'='application/json') ]),
	    json_read_dict(In, Reply),
	    close(In)).

%	A subprocess, per the module header. stderr is discarded: LE2 prints
%	load-time warnings that are not this program's diagnostics, and the
%	JSON we want is the last line of stdout.
run_le2(Dir, Goal, Out) :-
	atomic_list_concat([Dir, '/myswipl.sh'], Wrapper),
	( exists_file(Wrapper) -> Exe = Wrapper ; Exe = path(swipl) ),
	setup_call_cleanup(
	    process_create(Exe, ['-q', '-g', Goal, '-t', halt],
			   [ cwd(Dir), stdout(pipe(S)), stderr(null),
			     process(PID) ]),
	    read_string(S, _, Raw),
	    ( close(S), process_wait(PID, _) )),
	last_json_line(Raw, Out).

last_json_line(Raw, Out) :-
	split_string(Raw, "\n", " \t\r", Lines0),
	exclude(==(""), Lines0, Lines),
	reverse(Lines, [Last|_]),
	string_concat("{", _, Last),
	atom_string(Out, Last).
