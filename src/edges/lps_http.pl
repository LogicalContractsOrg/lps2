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

:- dynamic registered_program/2.   % Id, Program
:- dynamic registered_session/3.   % Id, Session, LastUsed
:- dynamic auth_token/1.
:- dynamic session_counter_http/1.

session_counter_http(0).

:- http_handler('/lpsapi', lpsapi, [method(post)]).
:- http_handler('/', ide_page, []).

%	The IDE (§I.10). The plan says to extend the LE2 Monaco editor; that
%	repository is not available here, so this is a self-contained page served
%	by the same endpoint, built around the same round-trip pattern LE2 uses —
%	a debounce, then a server-side analysis — and around the same operations
%	an LSP worker would call. Swapping the textarea for Monaco is then a
%	front-end change, not a protocol change.
ide_page(_Request) :-
	ide_file(File),
	read_file_to_string(File, Html, [encoding(utf8)]),
	format('Content-type: text/html; charset=UTF-8~n~n'),
	write(Html).

%!	example_source(+Name, -Text) is semidet.
example_source(Name, Text) :-
	example_path(Name, Path),
	exists_file(Path),
	read_file_to_string(Path, Text, [encoding(utf8)]).

example_path(Name, Path) :-
	lps_root(Root),
	member(Rel, ['/examples/', '/legacy_lps1/examples/CLOUT_workshop/']),
	atomic_list_concat([Root, Rel, Name, '.pl'], Path).

lps_root(Root) :-
	module_property(lps_http, file(F)),
	file_directory_name(F, Dir), file_directory_name(Dir, Src),
	file_directory_name(Src, Root).

ide_file(File) :-
	lps_root(Root),
	atomic_list_concat([Root, '/src/ide/index.html'], File).

%!	lps_server(+Port) is det.
lps_server(Port) :- lps_server(Port, []).

lps_server(Port, Options) :-
	(   memberchk(token(T), Options)
	->  retractall(auth_token(_)), assertz(auth_token(T))
	;   true
	),
	http_server(http_dispatch, [port(Port)]).

lps_stop(Port) :- http_stop_server(Port, []).

lpsapi(Request) :-
	http_read_json_dict(Request, Dict),
	(   authorised(Dict)
	->  catch(handle(Dict, Reply), E, error_reply(E, Reply))
	;   Reply = _{ok: false, error: "unauthorised"}
	),
	reply_json_dict(Reply).

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
	source_terms(Source, Terms0),
	apply_provenance(Dict, Terms0, Terms),
	lps_compile(terms(Terms), Syntax, [dc], Program, Diags),
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
	source_terms(Source, Terms0),
	apply_provenance(Dict, Terms0, Terms),
	lps_compile(terms(Terms), Syntax, [dc], _, Diags),
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
operation("scene", Dict, Reply) :- !,
	session_of(Dict, _, S),
	get_dict(cycle, Dict, C),
	lps_session_scene(S, C, scene(_, Timeless, Items)),
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

source_terms(Source, Terms) :-
	string(Source), !,
	setup_call_cleanup(
	    open_string(Source, In),
	    read_terms_in(In, Terms),
	    close(In)).
source_terms(Source, Terms) :-
	atom_string(A, Source), source_terms(A, Terms).

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
