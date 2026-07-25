/* lps_http.pl — the HTTP surface (§I.8.2).

   One POST endpoint dispatching on an `operation` field, with token auth —
   the LE2 pattern, deliberately, because it already works and the IDE will
   be a client of both.

     compile      source + syntax → program id + diagnostics
     session_new  program id → session id
     observe      inject events into a session
     step / run   advance one/several cycles, return CycleReports
     state        current fluents
     fork         open a hypothetical branch (§I.6)
     discard      drop one
     trace        the full trace, for the timeline UI
     dump         the internal syntax

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
:- use_module(library(http/http_json)).
:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../syntax/lps_internal_syntax').
:- use_module(lps_source).

:- dynamic registered_program/2.   % Id, Program
:- dynamic registered_session/3.   % Id, Session, LastUsed
:- dynamic auth_token/1.
:- dynamic session_counter_http/1.

session_counter_http(0).

:- http_handler('/lpsapi', lpsapi, [method(post)]).

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
	source_terms(Source, Terms),
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

read_terms_in(In, Terms) :-
	line_count(In, L0), L is L0 + 1,
	read_term(In, T, [module(lps_http)]),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [t(T, L)|More], read_terms_in(In, More)
	).

parse_term_string(S, T) :- term_string(T, S).
term_string_(T, S) :- format(string(S), '~q', [T]).

diag_dict(diag(Sev, Code, Pos, Msg, _), _{severity: SevS, code: CodeS, position: PosS, message: MsgS}) :-
	format(string(SevS), '~w', [Sev]),
	format(string(CodeS), '~w', [Code]),
	format(string(PosS), '~w', [Pos]),
	format(string(MsgS), '~w', [Msg]).

report_dict(cycle(Time, Events, Composites, Fluents, Actions),
	    _{time: Time, events: E, composites: C, fluents: F, actions: A}) :-
	maplist(term_string_, Events, E),
	maplist(term_string_, Composites, C),
	maplist(term_string_, Fluents, F),
	maplist(term_string_, Actions, A).

stage_dict(Stage, Cycle, Items, _{stage: S, cycle: Cycle, items: I}) :-
	format(string(S), '~w', [Stage]),
	maplist(term_string_, Items, I).
