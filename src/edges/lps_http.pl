/* lps_http.pl — the HTTP surface (§I.8.2).

   One POST endpoint dispatching on an `operation` field, with token auth —
   the LE2 pattern, deliberately, because it already works and the IDE will
   be a client of both.

     compile      source + syntax (+ provenance) → program id + diagnostics
     session_new  program id → session id
     observe      inject events into a session
     step / run   advance one/several cycles, return CycleReports
     state        current fluents
     fork         open a hypothetical branch (§I.6)
     discard      drop one
     trace        the full trace, for the timeline UI
     dump         the internal syntax
     analyse      compile only, and return diagnostics with source positions —
		  the LSP round trip of §I.10.1
     example      the text of a shipped example, by name
     explain      the five question forms of §I.10.5
     timeline     lanes and intervals for §I.10.2
     changes      the state-change diagram of §I.10.3
     scene        the display/2 visual mapping for a cycle (§I.10.4)
     automaton    the state-transitions diagram of the run (godfa/1)

   `compile` and `analyse` accept an optional `provenance` array alongside a
   `syntax: "internal"` source: one entry per source term, in term order,
   `{index, file, line, col, kind}`. That is how an LE-authored program
   (docs/le_lps_interface.md) gets its diagnostics reported at `.le`
   coordinates rather than at lines of the internal text LE2 generated.

   This is an *edge*: it may use threads freely, and does — the HTTP server is
   threaded. The core contract stays synchronous (`lps_session_step/3`), so a
   single-threaded deployment remains possible without changing a line of
   engine code.

   Cross-session isolation is structural, not module-based as it was upstream:
   two sessions are two terms in a registry, sharing one immutable program.
   Nothing one session does can be seen by another, which is what makes
   multi-program/multi-session safe rather than merely conventional.
*/

:- module(lps_http, [
	lps_server/1,            % +Port
	lps_server/2,            % +Port, +Options
	lps_stop/1               % +Port
	]).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_files)).
:- use_module(library(http/http_path)).
:- use_module(library(http/http_json)).
:- use_module(library(http/json)).
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
:- use_module(lps_assistant).
:- use_module(lps_live).
:- use_module(lps_wasm).

:- dynamic registered_program/2.   % Id, Program
:- dynamic registered_session/3.   % Id, Session, LastUsed
:- dynamic auth_token/1.
:- dynamic session_counter_http/1.

session_counter_http(0).

:- http_handler('/lpsapi', lpsapi, [methods([post, options])]).
:- http_handler('/', ide_page, [prefix]).
:- http_handler('/docs/', docs_page, [prefix]).
:- http_handler('/docs-raw/', docs_raw, [prefix]).
:- http_handler('/assets/', ide_asset, [prefix]).

/* The IDE (§I.10.1a, M14). Built by `npm --prefix ui run build` into
   src/ide/dist/ and served from here — the engine still has no build step and
   still needs no Node at run time, but Monaco, Konva and three.js are not
   things you paste into a page.

   Everything under dist/ is served flat, because that is what the bundler
   emits and what the page's own relative URLs ask for.
*/
ide_page(Request) :-
	memberchk(path(Path), Request),
	(   Path == '/'
	->  ide_dist_file('index.html', File), serve_file(File)
	;   atom_concat('/', Rel, Path),
	    ide_dist_file(Rel, File)
	->  serve_file(File)
	;   throw(http_reply(not_found(Path)))
	).

ide_asset(Request) :-
	memberchk(path(Path), Request),
	atom_concat('/assets/', Rel, Path),
	(   ide_dist_file(Rel, File)
	->  serve_file(File)
	;   throw(http_reply(not_found(Path)))
	).

%	`/docs/lps_summary` is the Help menu's target: the shell page, which then
%	fetches the markdown from /docs-raw/. LE2 serves /docs/le_summary the same
%	way, and the container already carries docs/.
docs_page(Request) :-
	memberchk(path(Path), Request),
	atom_concat('/docs/', Name, Path),
	(   Name == '' -> Doc = lps_summary ; Doc = Name ),
	(   ide_dist_file('doc.html', File)
	->  read_file_to_string(File, Html0, [encoding(utf8)]),
	    %  The shell fetches ?doc=NAME; putting the name in the page rather
	    %  than in the query string keeps the Help links plain.
	    format(atom(Inject), '<script>window.LPS_DOC=~q;</script>', [Doc]),
	    ( sub_atom(Html0, B, _, A, '</head>')
	    ->  sub_atom(Html0, 0, B, _, Pre), sub_atom(Html0, _, A, 0, Post),
	        atomic_list_concat([Pre, Inject, '</head>', Post], Html)
	    ;   Html = Html0 ),
	    format('Content-type: text/html; charset=UTF-8~n~n'),
	    write(Html)
	;   throw(http_reply(not_found(Path)))
	).

docs_raw(Request) :-
	memberchk(path(Path), Request),
	atom_concat('/docs-raw/', Name0, Path),
	safe_name(Name0, Name),
	lps_root(Root),
	atomic_list_concat([Root, '/docs/', Name], File),
	(   exists_file(File)
	->  serve_file(File)
	;   throw(http_reply(not_found(Path)))
	).

%	No traversal: a document name is a bare file name under docs/.
safe_name(N, N) :-
	\+ sub_atom(N, _, _, _, '..'),
	\+ sub_atom(N, 0, _, _, '/').

serve_file(File) :-
	file_mime(File, Mime),
	(   sub_atom(Mime, 0, _, _, 'text/') ; sub_atom(Mime, _, _, _, 'javascript')
	;   sub_atom(Mime, _, _, _, 'json') ; sub_atom(Mime, _, _, _, 'svg')
	),
	!,
	read_file_to_string(File, S, [encoding(utf8)]),
	format('Content-type: ~w; charset=UTF-8~n~n', [Mime]),
	write(S).
serve_file(File) :-
	file_mime(File, Mime),
	read_file_to_codes_bin(File, Codes),
	format('Content-type: ~w~n~n', [Mime]),
	forall(member(C, Codes), put_byte(C)).

read_file_to_codes_bin(File, Codes) :-
	setup_call_cleanup(open(File, read, S, [type(binary)]),
			   read_stream_to_codes(S, Codes),
			   close(S)).

file_mime(File, Mime) :-
	file_name_extension(_, Ext, File),
	( mime_of(Ext, Mime) -> true ; Mime = 'application/octet-stream' ).

mime_of(html, 'text/html').
mime_of(js,   'text/javascript').
mime_of(mjs,  'text/javascript').
mime_of(css,  'text/css').
mime_of(json, 'application/json').
mime_of(svg,  'image/svg+xml').
mime_of(png,  'image/png').
mime_of(jpg,  'image/jpeg').
mime_of(ttf,  'font/ttf').
mime_of(woff, 'font/woff').
mime_of(woff2,'font/woff2').
mime_of(wasm, 'application/wasm').
mime_of(data, 'application/octet-stream').
mime_of(md,   'text/markdown').
mime_of(txt,  'text/plain').

ide_dist_file(Rel, File) :-
	\+ sub_atom(Rel, _, _, _, '..'),
	lps_root(Root),
	atomic_list_concat([Root, '/src/ide/dist/', Rel], File),
	exists_file(File).

%!	example_source(+Name, -Text) is semidet.
%
%	Names may be paths under the corpus (`CLOUT_workshop/badlight`), which is
%	what list_examples returns, or bare names, which is what the older API
%	took and what a `?example=` link still carries.
example_source(Name, Text) :-
	example_path(Name, Path),
	exists_file(Path),
	read_file_to_string(Path, Text, [encoding(utf8)]).

example_path(Name, Path) :-
	lps_root(Root),
	member(Rel, ['/examples/', '/legacy_lps1/examples/',
		     '/legacy_lps1/examples/CLOUT_workshop/']),
	member(Ext, ['', '.pl', '.lps']),
	atomic_list_concat([Root, Rel, Name, Ext], Path).

lps_root(Root) :-
	module_property(lps_http, file(F)),
	file_directory_name(F, Dir), file_directory_name(Dir, Src),
	file_directory_name(Src, Root).

/* Every example the server can offer, with a one-line description taken from
   the program's own first comment. 160 corpus programs plus ours: §I.10.1a
   asks for any of them to be two clicks from a run, and curation for the
   tutorial and the assistant needs the list before it can start. */
example_list(Examples) :-
	lps_root(Root),
	findall(_{name: Rel, title: Title, dir: DirName},
		( example_dir(Dir, DirName),
		  atomic_list_concat([Root, '/', Dir], Full),
		  exists_directory(Full),
		  directory_files(Full, Files),
		  member(F, Files),
		  file_name_extension(_, Ext, F),
		  memberchk(Ext, [pl, lps]),
		  \+ sub_atom(F, _, _, _, '_.P'),
		  atomic_list_concat([Full, '/', F], Path),
		  exists_file(Path),
		  example_rel(Dir, F, Rel),
		  example_title(Path, Title) ),
		Examples0),
	sort(name, @<, Examples0, Examples).

example_dir('examples', 'LPS(2)').
example_dir('legacy_lps1/examples', 'corpus').
example_dir('legacy_lps1/examples/CLOUT_workshop', 'CLOUT workshop').
example_dir('legacy_lps1/examples/CLOUT_workshop/simulation', 'simulation').
example_dir('legacy_lps1/examples/forTesting', 'forTesting').
example_dir('legacy_lps1/examples/survival_game', 'survival game').
example_dir('examples/rkbook', 'Kowalski book').
example_dir('examples/pddl', 'PDDL').
example_dir('examples/drools', 'Drools').
example_dir('examples/minecraft', 'Minecraft').
example_dir('examples/agent', 'agent').

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
	;   sub_string(L, 0, _, _, "%")
	->  normalize_space(string(T1), L),
	    ( string_concat("% ", T, T1) -> Title = T ; Title = T1 )
	;   sub_string(L, 0, _, _, "/*")
	->  normalize_space(string(T2), L),
	    ( string_concat("/* ", T3, T2) -> Title = T3 ; Title = T2 )
	;   first_comment(S, Title)
	).

%!	lps_server(+Port) is det.
lps_server(Port) :- lps_server(Port, []).

lps_server(Port, Options) :-
	(   memberchk(token(T), Options)
	->  retractall(auth_token(_)), assertz(auth_token(T))
	;   true
	),
	http_server(http_dispatch, [port(Port)]).

lps_stop(Port) :- http_stop_server(Port, []).

/* Cross-origin, deliberately. The editor that drives this endpoint is served
   by LE2 on another port (docs/le_lps_design.md §3: two backends, no proxy), so
   every request from it is cross-origin and a browser will not send one without
   these headers. LPS_ORIGIN pins the allowed origin for a deployment; with none
   set it is `*`, which is right for a laptop and wrong for a public server —
   which is why LPS_TOKEN exists and why docs/deploy.md says to set it.
*/
lpsapi(Request) :-
	memberchk(method(options), Request), !,
	cors_headers,
	format('Content-type: text/plain~n~n').
lpsapi(Request) :-
	http_read_json_dict(Request, Dict),
	(   authorised(Dict)
	->  catch(handle(Dict, Reply), E, error_reply(E, Reply))
	;   Reply = _{ok: false, error: "unauthorised"}
	),
	cors_headers,
	reply_json_dict(Reply).

cors_headers :-
	( getenv('LPS_ORIGIN', O), O \== '' -> Origin = O ; Origin = '*' ),
	format('Access-Control-Allow-Origin: ~w~n', [Origin]),
	format('Access-Control-Allow-Methods: POST, OPTIONS~n', []),
	format('Access-Control-Allow-Headers: Content-Type~n', []),
	format('Access-Control-Max-Age: 86400~n', []).

authorised(Dict) :-
	(   auth_token(T)
	->  get_dict(token, Dict, T)
	;   true                       % no token configured: local development
	).

error_reply(E, _{ok: false, error: Msg}) :-
	message_to_codes_(E, Msg).

message_to_codes_(E, S) :- format(string(S), '~q', [E]).

		 /*******************************
		 *	   operations		*
		 *******************************/

handle(Dict, Reply) :-
	get_dict(operation, Dict, Op),
	operation(Op, Dict, Reply).

operation("compile", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(syntax, Dict, SyntaxS) -> atom_string(Syntax, SyntaxS) ; Syntax = legacy ),
	source_terms(Source, Terms0, ReadDiags),
	apply_provenance(Dict, Terms0, Terms),
	lps_compile(terms(Terms), Syntax, [dc], Program, CDiags),
	append(ReadDiags, CDiags, Diags),
	maplist(diag_dict, Diags, DiagDicts),
	(   diags_ok(Diags)
	->  prog_id(Program, Id),
	    retractall(registered_program(Id, _)),
	    assertz(registered_program(Id, Program)),
	    Reply = _{ok: true, program: Id, diagnostics: DiagDicts}
	;   Reply = _{ok: false, diagnostics: DiagDicts}
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
	lps_session_run(S0, Stop, S, _),
	update_session(Id, S),
	lps_session_status(S, Status), lps_session_time(S, Time),
	format(string(StatusS), '~w', [Status]),
	Reply = _{ok: true, session: Id, status: StatusS, cycle: Time}.
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
	retractall(registered_session(Id, _, _)),
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
	( get_dict(name, Dict, N) -> true ; N = "goat_declarative" ),
	atom_string(Name, N),
	(   example_source(Name, Text)
	->  Reply = _{ok: true, name: N, source: Text}
	;   format(string(M), 'no such example: ~w', [Name]),
	    Reply = _{ok: false, error: M}
	).
operation("analyse", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(syntax, Dict, SyntaxS) -> atom_string(Syntax, SyntaxS) ; Syntax = legacy ),
	source_terms(Source, Terms0, ReadDiags),
	apply_provenance(Dict, Terms0, Terms),
	lps_compile(terms(Terms), Syntax, [dc], _, CDiags),
	append(ReadDiags, CDiags, Diags),
	maplist(diag_dict, Diags, DiagDicts),
	Reply = _{ok: true, diagnostics: DiagDicts}.
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
	Reply = _{ok: true, cycles: Max, fluents: FL, events: EL, composites: CL}.
operation("changes", Dict, Reply) :- !,
	session_of(Dict, _, S),
	get_dict(cycle, Dict, C),
	lps_session_changes(S, C, changes(_, I, T, U, Persisted)),
	maplist(change_dict, I, ID), maplist(change_dict, T, TD), maplist(change_dict, U, UD),
	maplist(term_string_, Persisted, PD),
	Reply = _{ok: true, cycle: C, initiated: ID, terminated: TD, updated: UD, persisted: PD}.
operation("live_start", Dict, Reply) :- !,
	program_of(Dict, Program),
	( get_dict(cycle_ms, Dict, Ms) -> Opts = [cycle_ms(Ms)] ; Opts = [] ),
	live_start(Program, Opts, Id),
	Reply = _{ok: true, live: Id}.
operation("live_status", Dict, Reply) :- !,
	live_id(Dict, Id), live_status(Id, Reply).
operation("live_observe", Dict, Reply) :- !,
	live_id(Dict, Id),
	get_dict(events, Dict, Events),
	live_observe(Id, Events, Reply).
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
	    Reply = _{ok: true, cycle: Cycle, timeless: TL, items: IV}
	;   Reply = _{ok: false, error: "no such live session"}
	).
operation("live_translate", Dict, Reply) :- !,
	live_id(Dict, Id),
	get_dict(text, Dict, Text),
	(   live_session(Id, S)
	->  lps_session_program(S, P),
	    ( get_dict(api_keys, Dict, Keys) -> true ; Keys = _{} ),
	    ( get_dict(model, Dict, M) -> true ; M = null ),
	    assistant_translate(P, Text, [keys(Keys), model(M)], Events),
	    Reply = _{ok: true, events: Events}
	;   Reply = _{ok: false, error: "no such live session"}
	).
operation("assistant_models", Dict, Reply) :- !,
	( get_dict(api_keys, Dict, Keys) -> true ; Keys = _{} ),
	lps_assistant:assistant_models(Keys, Models),
	Reply = _{ok: true, models: Models}.
operation("assistant_command", Dict, Reply) :- !,
	assistant_start(Dict, Job),
	Reply = _{ok: true, job: Job}.
operation("assistant_status", Dict, Reply) :- !,
	get_dict(job, Dict, JobS), atom_string(Job, JobS),
	assistant_status(Job, S),
	Reply = _{ok: true, status: S.status, output: S.output,
		  explanation: S.explanation, new_content: S.new_content,
		  error: S.error}.
operation("assistant_interrupt", Dict, Reply) :- !,
	get_dict(job, Dict, JobS), atom_string(Job, JobS),
	assistant_interrupt(Job),
	Reply = _{ok: true}.
operation("wasm_bundle", Dict, Reply) :- !,
	get_dict(source, Dict, Source),
	( get_dict(title, Dict, T) -> Title = T ; Title = "an LPS program" ),
	wasm_bundle(Source, [title(Title)], Html),
	Reply = _{ok: true, html: Html}.
operation("list_examples", _Dict, Reply) :- !,
	example_list(Examples),
	Reply = _{ok: true, examples: Examples}.
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

live_id(Dict, Id) :-
	get_dict(live, Dict, S), atom_string(Id, S).

		 /*******************************
		 *	    registry		*
		 *******************************/

program_of(Dict, Program) :-
	get_dict(program, Dict, IdS), atom_string(Id, IdS),
	(   registered_program(Id, Program)
	->  true
	;   throw(error(lps_no_such_program(Id), _))
	).

session_of(Dict, Id, S) :-
	get_dict(session, Dict, IdS), atom_string(Id, IdS),
	(   registered_session(Id, S, _)
	->  true
	;   throw(error(lps_no_such_session(Id), _))
	).

register_session(S, Id) :-
	retract(session_counter_http(N)), N1 is N + 1, assertz(session_counter_http(N1)),
	format(atom(Id), 's~w', [N1]),
	assertz(registered_session(Id, S, 0)).

update_session(Id, S) :-
	retractall(registered_session(Id, _, _)),
	assertz(registered_session(Id, S, 0)).

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
%	its own line. Documented in docs/le_lps_interface.md, §3.
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

read_terms_in(In, Terms) :-
	line_count(In, L0), L is L0 + 1,
	read_term(In, T, [module(lps_http)]),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [t(T, L)|More], read_terms_in(In, More)
	).

parse_term_string(S, T) :- term_string(T, S).
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

fluent_lane_dict(lane(F, Intervals), _{fluent: FS, intervals: IS}) :-
	term_string_(F, FS),
	maplist([interval(A, B), _{from: A, to: B}]>>true, Intervals, IS).

stage_lane_dict(lane(_, Cells), CD) :-
	maplist(cell_dict, Cells, CD).

cell_dict(cell(C, Items), _{cycle: C, items: IS}) :- maplist(term_string_, Items, IS).

change_dict(change(F, A, Src, _), _{fluent: FS, action: AS, source: SS}) :-
	term_string_(F, FS), term_string_(A, AS), format(string(SS), '~w', [Src]).

%	A node's identity is its list of cycles — that is what makes two visits
%	to the same state one state — so it travels as a string the front end
%	can use as a key without having to re-derive it.
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

visual_dict(visual(Kind, Subject, Props), _{kind: K, subject: S, props: P}) :-
	format(string(K), '~w', [Kind]),
	term_string_(Subject, S),
	props_dict(Props, P).

stage_dict(Stage, Cycle, Items, _{stage: S, cycle: Cycle, items: I}) :-
	format(string(S), '~w', [Stage]),
	maplist(term_string_, Items, I).
