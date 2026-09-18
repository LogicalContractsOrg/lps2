/* lps_mcp.pl — the Model Context Protocol surface (Part II, §II.2–§II.3).

   LPS over MCP is not the IDE's API with a different envelope. The IDE asks
   *what happened*; an agent asks three questions the IDE never needs to:

     may I do this?          propose_action/may — checked against the
			     integrity constraints, in place, before anything
			     is committed and without advancing the world
     what happens if I do?   simulate/what_would_violate — a run on a copy,
			     with the trunk left exactly where it was
     why did that happen?    explain — the five question forms of §I.10.5,
			     as English lines rather than a tree to render

   Everything else here exists to make those three answerable: a world to ask
   them of, a vocabulary to ask them in, and a state to ask them about.

   **Worlds.** MCP conversations are not sessions, so the server hands out
   explicit handles. A world is either *owned* — a session this server
   created and advances — or *attached*, a read-through handle on a live
   session (src/edges/lps_live.pl) that somebody else is driving. The same
   tools work on both; only `observe` takes a different road, because a live
   session has a driver and must be told rather than stepped.

   **Why propose_action does not fork.** `lps_session_fork/2` marks a session
   hypothetical, and a hypothetical world refuses observations by design
   (lps_session.pl: "a lookahead that quietly accepted exogenous events would
   be answering a different question"). The question here is exactly what
   happens when an exogenous event *is* accepted, so the probe is an ordinary
   trunk session value that is advanced and then dropped. Sessions are
   immutable terms: the registered world never sees it, and the two futures
   cannot interfere because there is nothing shared to interfere through.

   **Why the guardrail is not a run.** A constraint that refuses an action
   does so against the state the action is proposed in, so the answer is one
   evaluation of `p_d_pre/3` with the action unified into it, in the borrowed
   state — milliseconds, no cycle, no commitment (the pattern lps_play.pl
   uses for "would this command work?"). Running is what `simulate` is for,
   and it answers a bigger question: what the program does *next*.

   Transports: STDIO (`./lps mcp`) and HTTP (`POST /mcp` on the IDE server),
   the same two LE2's `llm/mcp.pl` offers, and the same JSON-RPC envelope, so
   one client configuration reaches either system.
*/

:- module(lps_mcp, [
	mcp_stdio/0,             % the STDIO server loop
	mcp_http/1,              % +Request            the POST /mcp handler
	mcp_message/2,           % +Message, -Reply    one JSON-RPC message
	mcp_call_tool/3,         % +Name, +Args, -Reply
	mcp_tools/1,             % -Tools
	mcp_forget_worlds/0      % drop every owned world (tests)
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(yall)).
:- use_module(library(pairs)).
:- use_module(library(terms), [variant/2]).
:- use_module(library(http/json)).
:- use_module(library(http/http_json)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../core/lps_explain').
:- use_module('../core/lps_query').
:- use_module('../core/lps_store').
:- use_module(lps_source).
:- use_module(lps_sandbox).
:- use_module(lps_ids).
:- use_module(lps_live).

:- dynamic world/3.              % Id, owned(Session) | attached(LiveId), Meta
:- dynamic world_counter/1.
world_counter(0).

%!      mcp_forget_worlds is det.
%
%       Drops every owned world. Attached ones go with their live session.
mcp_forget_worlds :-
	with_mutex(lps_mcp, retractall(world(_, _, _))).

		 /*******************************
		 *          transports          *
		 *******************************/

%!      mcp_stdio is det.
%
%       One JSON-RPC message per line on standard input, one reply per line
%       on standard output. Notifications (no `id`) are acted on and not
%       answered, as the protocol requires.
mcp_stdio :-
	set_stream(user_input, encoding(utf8)),
	set_stream(user_output, encoding(utf8)),
	stdio_loop.

stdio_loop :-
	catch(json_read_dict(user_input, Msg), _, Msg = end_of_file),
	(   Msg == end_of_file
	->  true
	;   (   is_dict(Msg), get_dict(id, Msg, _)
	    ->  mcp_message(Msg, Reply),
		json_write_dict(user_output, Reply, [width(0)]),
		nl(user_output),
		flush_output(user_output)
	    ;   ( is_dict(Msg) -> ignore(mcp_message(Msg, _)) ; true )
	    ),
	    stdio_loop
	).

%!      mcp_http(+Request) is det.
%
%       `POST /mcp`, one JSON-RPC message in, one JSON reply out. A GET is
%       answered 405: server-sent events are not implemented, and saying so
%       is better than a half-open stream.
mcp_http(Request) :-
	(   memberchk(method(post), Request)
	->  http_read_json_dict(Request, Msg),
	    (   is_dict(Msg), get_dict(id, Msg, _)
	    ->  mcp_message(Msg, Reply),
		reply_json_dict(Reply)
	    ;   ignore(mcp_message(Msg, _)),
		reply_json_dict(_{result: "ok"})
	    )
	;   memberchk(method(get), Request)
	->  reply_json_dict(_{error: "SSE not implemented, use POST JSON-RPC"},
			    [status(405)])
	;   reply_json_dict(_{error: "method not allowed"}, [status(405)])
	).

		 /*******************************
		 *          JSON-RPC            *
		 *******************************/

%!      mcp_message(+Message, -Reply) is det.
mcp_message(Msg, Reply) :-
	(   get_dict(id, Msg, Id) -> true ; Id = null ),
	(   get_dict(method, Msg, Method)
	->  (   catch(method(Method, Msg, Result), E, true)
	    ->  (   nonvar(E)
		->  error_reply(E, Id, Reply)
		;   Reply = _{jsonrpc: "2.0", id: Id, result: Result}
		)
	    ;   unknown_method(Method, Id, Reply)
	    )
	;   Reply = _{jsonrpc: "2.0", id: Id,
		      error: _{code: -32600, message: "no method in the request"}}
	).

unknown_method(Method, Id, Reply) :-
	format(string(M), 'method not found: ~w', [Method]),
	Reply = _{jsonrpc: "2.0", id: Id, error: _{code: -32601, message: M}}.

error_reply(E, Id, Reply) :-
	message_to_text(E, M),
	Reply = _{jsonrpc: "2.0", id: Id, error: _{code: -32603, message: M}}.

method("initialize", _, _{protocolVersion: "2024-11-05",
			  capabilities: _{tools: _{}, prompts: _{}, resources: _{}},
			  serverInfo: _{name: "LPS2 MCP Server", version: V}}) :-
	server_version(V).
method("notifications/initialized", _, _{}).
method("ping", _, _{}).
method("tools/list", _, _{tools: Tools}) :- mcp_tools(Tools).
method("tools/call", Msg, Result) :-
	get_dict(params, Msg, Params),
	get_dict(name, Params, Name0),
	clean_tool_name(Name0, Name),
	( get_dict(arguments, Params, Args), is_dict(Args) -> true ; Args = _{} ),
	mcp_call_tool(Name, Args, Reply),
	tool_result(Reply, Result).
method("prompts/list", _, _{prompts: Prompts}) :- mcp_prompts(Prompts).
method("prompts/get", Msg, Result) :-
	get_dict(params, Msg, Params),
	get_dict(name, Params, Name0), atom_string(Name, Name0),
	prompt_text(Name, Params, Text),
	Result = _{description: "LPS2", messages: [
		_{role: "user", content: _{type: "text", text: Text}}]}.
method("resources/list", _, _{resources: R}) :- mcp_resources(R).
method("resources/read", Msg, _{contents: [_{uri: Uri, mimeType: "text/markdown", text: Text}]}) :-
	get_dict(params, Msg, Params),
	get_dict(uri, Params, Uri0), atom_string(Uri, Uri0),
	resource_text(Uri, Text).

server_version("1").

%       An LLM sometimes appends channel junk to a tool name
%       (`observe<|channel|>…`); LE2's server cuts at the `<` and so do we.
clean_tool_name(N0, Name) :-
	atom_string(A, N0),
	( sub_atom(A, B, _, _, '<') -> sub_atom(A, 0, B, _, Name) ; Name = A ).

%       A tool's reply is its JSON, as the text of one content item — the
%       shape every MCP client renders. `error` in the reply also sets
%       isError, so a client that only looks at the flag still sees it.
tool_result(Reply, _{content: [_{type: "text", text: Text}], isError: IsError}) :-
	( get_dict(error, Reply, _) -> IsError = true ; IsError = false ),
	with_output_to(string(Text), json_write_dict(current_output, Reply, [width(0)])).

message_to_text(error(mcp_error(M0), _), M) :- !, atom_string(M0, M).
message_to_text(error(mcp_no_world, _), M) :- !,
	M = "give `world`: the handle open_world or attach_live returned".
message_to_text(error(lps_hypothetical_world_is_closed(_), _), M) :- !,
	M = "this world is a lookahead and does not accept observations".
message_to_text(error(existence_error(procedure, PI), _), M) :- !,
	format(string(M), 'this server has no ~q', [PI]).
message_to_text(error(type_error(Type, Value), _), M) :- !,
	format(string(M), 'expected ~w, got ~q', [Type, Value]).
message_to_text(error(E, _), M) :- !, format(string(M), '~q', [E]).
message_to_text(E, M) :- format(string(M), '~q', [E]).

		 /*******************************
		 *        the tool table        *
		 *******************************/

%!      mcp_tools(-Tools) is det.
%
%       The catalogue, in the order an agent meets them: find a program, open
%       a world, look at it, ask permission, look ahead, ask why.
mcp_tools(Tools) :-
	findall(_{name: N, description: D, inputSchema: S},
		tool(N, D, S), Tools).

tool("list_programs",
     "List the LPS programs this server ships (examples, Logical English for LPS, \
migrated twins). Use the `name` of one to open a world.",
     _{type: "object", properties: _{
	 match: _{type: "string", description: "only names containing this text"}},
       required: []}).

tool("open_world",
     "Open a world: compile a program and start a session of it. Returns the world \
handle every other tool takes, the vocabulary the program speaks (its events, actions \
and fluents), the integrity constraints that will refuse things, and the state.",
     _{type: "object", properties: _{
	 program: _{type: "string", description: "a name from list_programs, or a file path"},
	 source: _{type: "string", description: "program text, instead of `program`"},
	 syntax: _{type: "string", description: "with `source`: lps (default), internal or le"},
	 run: _{type: "integer", description: "advance this many cycles after opening (default 1)"}},
       required: []}).

tool("list_worlds", "The worlds this session has open.",
     _{type: "object", properties: _{}, required: []}).

tool("world_status",
     "Where a world stands: its cycle, whether it is still running, how many fluents \
hold, and anything an integrity constraint has refused so far.",
     _{type: "object", properties: _{world: _{type: "string"}}, required: ["world"]}).

tool("close_world", "Forget an owned world. An attached live session keeps running.",
     _{type: "object", properties: _{world: _{type: "string"}}, required: ["world"]}).

tool("list_live",
     "The live sessions running on this server — programs somebody else is driving, \
which attach_live can watch.",
     _{type: "object", properties: _{}, required: []}).

tool("attach_live",
     "Attach a world handle to a running live session, to watch and question it. \
Reading tools work as usual; `observe` sends events to its driver.",
     _{type: "object", properties: _{live: _{type: "string", description: "a live id from list_live"}},
       required: ["live"]}).

tool("state",
     "What holds now, or at a past cycle. `match` filters by functor, e.g. balance.",
     _{type: "object", properties: _{
	 world: _{type: "string"},
	 at: _{type: "integer", description: "a past cycle; default the current one"},
	 match: _{type: "string", description: "only fluents whose text contains this"}},
       required: ["world"]}).

tool("observe",
     "Tell the world that something happened, and let it react. This advances the \
world: to ask what *would* happen, use propose_action or simulate instead. Reports what \
changed, what the program did, and whether an integrity constraint refused the event.",
     _{type: "object", properties: _{
	 world: _{type: "string"},
	 events: _{type: "array", items: _{type: "string"},
		   description: "event terms, e.g. [\"window(open)\"]"},
	 cycles: _{type: "integer", description: "how many cycles to run afterwards; \
default: until the world goes quiet"}},
       required: ["world", "events"]}).

tool("propose_action",
     "May this be done, here, now? Checks the action against every integrity \
constraint in the state the world is actually in, and — unless it is refused — reports \
what would follow. The world is NOT advanced: this is the guardrail an agent asks \
before acting.",
     _{type: "object", properties: _{
	 world: _{type: "string"},
	 action: _{type: "string", description: "an action or event term, e.g. \"heat(on)\""},
	 cycles: _{type: "integer", description: "how far to look ahead for consequences (default 3)"}},
       required: ["world", "action"]}).

tool("may",
     "Which of the world's actions are permitted right now, and which are refused, \
with the constraint that refuses each. Answers \"who may do what\" for a contract or a \
ledger, from the program rather than from memory.",
     _{type: "object", properties: _{
	 world: _{type: "string"},
	 candidates: _{type: "array", items: _{type: "string"},
		       description: "terms to test; default every declared action, \
with its arguments taken from the values in play"},
	 limit: _{type: "integer", description: "most candidates to report (default 40)"}},
       required: ["world"]}).

tool("simulate",
     "If these events happen, what follows? Runs a copy of the world — the real one \
is untouched — and reports the timeline, what each cycle did, anything refused, any \
constraint violated, and the state it ends in.",
     _{type: "object", properties: _{
	 world: _{type: "string"},
	 events: _{type: "array", description: "either \"term\" or {event, after} where \
`after` delays it by that many cycles",
		   items: _{type: "object"}},
	 cycles: _{type: "integer", description: "cycles to run (default 6)"}},
       required: ["world"]}).

tool("what_would_violate",
     "Which of these events would break something: refused by a constraint, or \
leading the program into a violation within the window. Each candidate is tried on its \
own copy of the world.",
     _{type: "object", properties: _{
	 world: _{type: "string"},
	 candidates: _{type: "array", items: _{type: "string"}},
	 cycles: _{type: "integer", description: "the window, in cycles (default 3)"}},
       required: ["world"]}).

tool("timeline",
     "The run so far: each fluent's intervals, the events and composite events of each \
cycle, and every observation an integrity constraint refused.",
     _{type: "object", properties: _{world: _{type: "string"}}, required: ["world"]}).

tool("changes",
     "What changed in one cycle and what caused it: the fluents initiated, terminated \
and updated, each with the event responsible. This is the `cause_of` question.",
     _{type: "object", properties: _{
	 world: _{type: "string"}, cycle: _{type: "integer"}},
       required: ["world", "cycle"]}).

tool("explain",
     "Why did that happen, or why did it not? The five questions are why/why_not of \
happened(Action) and holds(Fluent), and why(stopped(Fluent)). Answered in English from \
the recorded run.",
     _{type: "object", properties: _{
	 world: _{type: "string"},
	 question: _{type: "string", description: "a question term, e.g. \
\"why_not(happened(heat(on)), 4)\""},
	 kind: _{type: "string", description: "instead of `question`: why, why_not"},
	 what: _{type: "string", description: "with `kind`: happened(A), holds(F) or stopped(F)"},
	 at: _{type: "integer", description: "with `kind`: the cycle (default: now)"}},
       required: ["world"]}).

tool("obligations",
     "What the world still owes: the commitments reactive rules have created and not \
yet discharged. An agent reads this to know what is outstanding and by when.",
     _{type: "object", properties: _{world: _{type: "string"}}, required: ["world"]}).

tool("find_first",
     "The first cycle at which something held, or happened — a search over the \
recorded run rather than a recollection of it.",
     _{type: "object", properties: _{
	 world: _{type: "string"},
	 holds: _{type: "string", description: "a fluent term, variables allowed: \"balance(bob, _)\""},
	 happened: _{type: "string", description: "an event term, instead of `holds`"}},
       required: ["world"]}).

tool("plan",
     "What this world will do next if nothing else happens: the actions of each cycle, \
from a lookahead that leaves the world untouched. For a program in planning mode it is \
the plan the planner found.",
     _{type: "object", properties: _{
	 world: _{type: "string"},
	 cycles: _{type: "integer", description: "how far ahead (default 10)"}},
       required: ["world"]}).

		 /*******************************
		 *          prompts             *
		 *******************************/

mcp_prompts([_{name: "act_within_the_rules",
	       description: "Work inside an LPS world: check before acting, act, explain.",
	       arguments: [_{name: "program", description: "the program to open", required: (false)}]},
	     _{name: "watch_a_live_run",
	       description: "Attach to a running live session and monitor it.",
	       arguments: [_{name: "live", description: "the live id", required: (false)}]}]).

prompt_text(act_within_the_rules, Params, Text) :-
	( get_dict(arguments, Params, A), get_dict(program, A, P) -> true ; P = "start/thermostat" ),
	format(string(Text),
	       'Open the LPS world `~w` with open_world. Read its vocabulary: you may \c
only speak of the events and actions it declares, in exactly those terms. Before doing \c
anything, call propose_action and act only if it answers permitted; if it is refused, \c
report the constraint that refused it in its own words rather than working around it. \c
Use simulate to compare options before you choose. After acting, use explain to say why \c
what happened happened. Never assert what holds in the world from memory — ask `state`.',
	       [P]).
prompt_text(watch_a_live_run, Params, Text) :-
	( get_dict(arguments, Params, A), get_dict(live, A, L) -> true ; L = "" ),
	format(string(Text),
	       'Call list_live, then attach_live (live: "~w" if that is not empty). \c
Watch with world_status, state and timeline. When something was refused or a constraint \c
was violated, use changes and explain to say what caused it, citing the cycle. Use \c
what_would_violate to warn about what is about to go wrong. Do not send events unless \c
you are asked to: you are monitoring a run somebody else is driving.', [L]).

mcp_resources([_{uri: "lps://docs/language", name: "The LPS language reference",
		 mimeType: "text/markdown"},
	       _{uri: "lps://docs/le-for-lps", name: "Logical English for LPS",
		 mimeType: "text/markdown"}]).

resource_text('lps://docs/language', Text) :- doc_text('docs/user/reference/lps.md', Text).
resource_text('lps://docs/le-for-lps', Text) :- doc_text('docs/user/reference/le-for-lps.md', Text).

doc_text(Rel, Text) :-
	lps_root_dir(Root),
	atomic_list_concat([Root, '/', Rel], Path),
	(   exists_file(Path)
	->  read_file_to_string(Path, Text, [encoding(utf8)])
	;   format(string(Text), 'not found: ~w', [Rel])
	).

		 /*******************************
		 *          the tools           *
		 *******************************/

%!      mcp_call_tool(+Name, +Args, -Reply) is det.
%
%       Never fails and never throws: a tool that cannot answer says so in
%       an `error` field, because an agent can read that and a protocol
%       error is only a dead end.
mcp_call_tool(Name0, Args, Reply) :-
	%  A tool name arrives as an atom from the JSON-RPC layer and as a
	%  string from a Prolog caller; the table is written in strings.
	( string(Name0) -> Name = Name0 ; atom_string(Name0, Name) ),
	(   catch(tool_call(Name, Args, R), E, ( message_to_text(E, M), R = _{error: M} ))
	->  Reply = R
	;   format(string(M2), 'no answer from ~w — check its arguments', [Name]),
	    Reply = _{error: M2}
	).

tool_call("list_programs", Args, _{programs: Programs, count: N}) :-
	( arg_text(Args, match, '', Match) -> true ; Match = '' ),
	findall(Name-Title,
		( shipped_program(Name, Title),
		  ( Match == '' -> true ; matches_text(Name, Match) ; matches_text(Title, Match) )),
		Pairs0),
	keysort(Pairs0, Sorted),
	group_pairs_by_key(Sorted, Grouped),
	findall(_{name: Name, title: Title},
		( member(Name-[Title|_], Grouped) ), Programs),
	length(Programs, N).

tool_call("open_world", Args, Reply) :-
	load_program(Args, Program, Name, Diags),
	(   Program == none
	->  diag_texts(Diags, DT),
	    Reply = _{error: "the program did not compile", diagnostics: DT}
	;   lps_session_new(Program, [dc], S0),
	    arg_int(Args, run, 1, N),
	    ( N > 0 -> lps_session_run(S0, cycles(N), S, _) ; S = S0 ),
	    new_world(owned(S), _{program: Name}, Id),
	    world_overview(Id, S, Overview),
	    diag_texts(Diags, DT),
	    Reply = Overview.put(_{diagnostics: DT})
	).

tool_call("list_worlds", _, _{worlds: Ws}) :-
	findall(_{world: Id, program: P, kind: K, cycle: C, status: St},
		( world(Id, Ref, Meta),
		  ( get_dict(program, Meta, P) -> true ; P = "" ),
		  ( Ref = owned(_) -> K = "owned" ; K = "live" ),
		  ( world_session(Id, S)
		  -> lps_session_time(S, C), status_text(S, St)
		  ;  C = 0, St = "gone" ) ),
		Ws).

tool_call("world_status", Args, Reply) :-
	world_of(Args, Id, S),
	lps_session_time(S, C), status_text(S, St),
	lps_session_state(S, Fluents), length(Fluents, NF),
	lps_session_refused(S, Refused), refused_dicts(Refused, RD),
	violations(S, 0, Viol),
	world_kind(Id, K),
	Reply = _{world: Id, cycle: C, status: St, kind: K, fluents: NF,
		  refused: RD, violations: Viol}.

tool_call("close_world", Args, _{world: Id, closed: Was}) :-
	arg_text(Args, world, '', Id),
	( world(Id, _, _) -> Was = true ; Was = (false) ),
	with_mutex(lps_mcp, retractall(world(Id, _, _))).

tool_call("list_live", _, _{live: L}) :-
	findall(_{live: Id, status: St, cycle: C},
		( live_ids(Id), live_status(Id, D),
		  ( get_dict(status, D, St) -> true ; St = "?" ),
		  ( get_dict(cycle, D, C) -> true ; C = 0 ) ),
		L).

tool_call("attach_live", Args, Reply) :-
	arg_text(Args, live, '', Live),
	(   lps_live:live_session(Live, S)
	->  new_world(attached(Live), _{program: Live}, Id),
	    world_overview(Id, S, Reply)
	;   format(string(M), 'no live session ~w — call list_live', [Live]),
	    Reply = _{error: M}
	).

tool_call("state", Args, Reply) :-
	world_of(Args, Id, S),
	lps_session_time(S, Now),
	(   arg_int_opt(Args, at, At)
	->  ( state_at(S, At, Fluents) -> true ; Fluents = [] ), Cycle = At
	;   lps_session_state(S, Fluents), Cycle = Now
	),
	arg_text(Args, match, '', Match),
	filter_terms(Fluents, Match, Kept),
	terms_texts(Kept, Texts),
	length(Texts, N),
	Reply = _{world: Id, cycle: Cycle, fluents: Texts, count: N}.

tool_call("observe", Args, Reply) :-
	world_of(Args, Id, S0),
	arg_terms(Args, events, Events, Texts),
	(   world(Id, attached(Live), _)
	->  live_observe(Live, Texts, R),
	    Reply = _{world: Id, sent_to_live: Live, result: R}
	;   lps_session_time(S0, T0),
	    lps_session_observe(S0, Events, S1),
	    (   arg_int_opt(Args, cycles, N)
	    ->  lps_session_run(S1, cycles(N), S2, _), Reports = []
	    ;   settle(S1, S2, Reports)
	    ),
	    update_world(Id, S2),
	    after_report(Id, S0, S2, T0, Reports, Texts, Reply)
	).

%       The guardrail. Two answers in one: may it be done (the constraints,
%       evaluated in the state the world is in), and what would follow if it
%       were (a probe run that is thrown away).
tool_call("propose_action", Args, Reply) :-
	world_of(Args, Id, S),
	arg_term(Args, action, Action, Text),
	refusals(S, Action, Refusals),
	arg_int(Args, cycles, 3, N),
	(   Refusals \== []
	->  refusal_dicts(S, Refusals, RD),
	    why_not_lines(S, Action, Lines),
	    Reply = _{world: Id, action: Text, permitted: (false),
		      refused_by: RD, why_not: Lines,
		      note: "the world was not advanced"}
	;   lps_session_time(S, T0),
	    (   catch(( lps_session_observe(S, [Action], P1),
			lps_session_run(P1, cycles(N), P2, _) ), _, fail)
	    ->  consequences(S, P2, T0, Cons),
		Reply = _{world: Id, action: Text, permitted: true,
			  consequences: Cons, note: "the world was not advanced"}
	    ;   Reply = _{world: Id, action: Text, permitted: true,
			  consequences: _{note: "the lookahead could not be run"},
			  note: "the world was not advanced"}
	    )
	).

tool_call("may", Args, Reply) :-
	world_of(Args, Id, S),
	arg_int(Args, limit, 40, Limit),
	(   arg_terms_opt(Args, candidates, Cands, CTexts)
	->  true
	;   declared_actions(S, Cands), terms_texts(Cands, CTexts)
	),
	pairs_upto(Cands, CTexts, Limit, Pairs),
	findall(D, ( member(A-T, Pairs), may_dict(S, A, T, D) ), Ds),
	lps_session_time(S, C),
	Reply = _{world: Id, cycle: C, actions: Ds}.

tool_call("simulate", Args, Reply) :-
	world_of(Args, Id, S),
	arg_int(Args, cycles, 6, N),
	schedule(Args, Schedule),
	lps_session_time(S, T0),
	run_schedule(S, Schedule, N, S2),
	consequences(S, S2, T0, Cons),
	lps_session_timeline(S2, TL), timeline_dict(S2, TL, TLD),
	lps_session_state(S2, Fl), terms_texts(Fl, FT),
	schedule_texts(Schedule, ST),
	Reply = _{world: Id, ran_from: T0, events: ST, consequences: Cons,
		  timeline: TLD, final_state: FT, note: "the world was not advanced"}.

tool_call("what_would_violate", Args, Reply) :-
	world_of(Args, Id, S),
	arg_int(Args, cycles, 3, N),
	(   arg_terms_opt(Args, candidates, Cands, CTexts)
	->  true
	;   declared_actions(S, Cands), terms_texts(Cands, CTexts)
	),
	pairs_upto(Cands, CTexts, 40, Pairs),
	findall(D, ( member(A-T, Pairs), would_violate(S, A, T, N, D) ), Ds),
	include([X]>>( get_dict(outcome, X, O), O \== "nothing breaks" ), Ds, Bad),
	Reply = _{world: Id, tested: Ds, breaking: Bad}.

tool_call("timeline", Args, Reply) :-
	world_of(Args, Id, S),
	lps_session_timeline(S, TL),
	timeline_dict(S, TL, D),
	Reply = D.put(world, Id).

tool_call("changes", Args, Reply) :-
	world_of(Args, Id, S),
	arg_int(Args, cycle, 1, C),
	(   catch(lps_session_changes(S, C, changes(_, I, T, U, Persisted)), _, fail)
	->  maplist(change_dict, I, ID), maplist(change_dict, T, TD),
	    maplist(change_dict, U, UD), terms_texts(Persisted, PD),
	    Reply = _{world: Id, cycle: C, initiated: ID, terminated: TD,
		      updated: UD, unchanged: PD}
	;   format(string(M), 'no cycle ~w in this run', [C]),
	    Reply = _{error: M}
	).

tool_call("explain", Args, Reply) :-
	world_of(Args, Id, S),
	(   question_term(Args, S, Q, QText)
	->  (   catch(lps_session_explain(S, Q, E), _, fail),
		E = explanation(_, Verdict, _)
	    ->  explanation_text(E, Lines0), strings_of(Lines0, Lines),
		format(string(V), '~w', [Verdict]),
		Reply = _{world: Id, question: QText, verdict: V, explanation: Lines}
	    ;   Reply = _{error: "the run does not answer that question",
			  question: QText}
	    )
	;   Reply = _{error: "give `question`, or `kind` with `what`: \c
why(happened(A), T), why(holds(F), T), why(stopped(F), T), \c
why_not(happened(A), T), why_not(holds(F), T)"}
	).

tool_call("obligations", Args, Reply) :-
	world_of(Args, Id, S),
	lps_session_time(S, C),
	outstanding(S, Obligations),
	length(Obligations, N),
	Reply = _{world: Id, cycle: C, outstanding: Obligations, count: N}.

tool_call("find_first", Args, Reply) :-
	world_of(Args, Id, S),
	(   arg_term_opt(Args, holds, F, FT)
	->  Stage = (fluents), Pattern = F, PText = FT, Kind = "holds"
	;   arg_term_opt(Args, happened, Ev, ET)
	->  Stage = (events), Pattern = Ev, PText = ET, Kind = "happened"
	;   throw(error(mcp_error('give `holds` or `happened`, a term'), _))
	),
	(   first_stage_match(S, Stage, Pattern, Cycle, Item)
	->  term_text(Item, IT),
	    Reply = _{world: Id, looked_for: PText, kind: Kind, found: true,
		      cycle: Cycle, item: IT}
	;   Reply = _{world: Id, looked_for: PText, kind: Kind, found: (false)}
	).

tool_call("plan", Args, Reply) :-
	world_of(Args, Id, S),
	arg_int(Args, cycles, 10, N),
	lps_session_time(S, T0),
	lps_session_fork(S, F0),
	catch(lps_session_run(F0, cycles(N), F, _), _, F = F0),
	lps_session_program(F, P),
	findall(_{cycle: C, actions: As},
		( between_cycles(T0, F, C), cycle_actions(F, P, C, As), As \== [] ),
		Steps),
	status_text(F, St),
	Reply = _{world: Id, from: T0, steps: Steps, status_after: St,
		  note: "a lookahead: the world was not advanced"}.

		 /*******************************
		 *           worlds             *
		 *******************************/

new_world(Ref, Meta, Id) :-
	with_mutex(lps_mcp,
		   (   retract(world_counter(N)), N1 is N + 1, assertz(world_counter(N1)),
		       format(atom(Base), 'w~w', [N1]),
		       tagged_id(Base, Id),
		       assertz(world(Id, Ref, Meta))
		   )).

%!      world_session(+Id, -Session) is semidet.
%
%       An owned world holds its session; an attached one reads the live
%       session through every time, so the agent sees the run as it is now
%       rather than as it was when it attached.
world_session(Id, S) :-
	once(world(Id, Ref, _)),
	(   Ref = owned(S0)
	->  S = S0
	;   Ref = attached(Live),
	    lps_live:live_session(Live, S)
	).

world_of(Args, Id, S) :-
	arg_text(Args, world, '', Id),
	(   Id == ''
	->  throw(error(mcp_no_world, _))
	;   world_session(Id, S)
	->  true
	;   format(atom(M), 'no world ~w — open_world first, or list_worlds', [Id]),
	    throw(error(mcp_error(M), _))
	).

update_world(Id, S) :-
	with_mutex(lps_mcp,
		   (   retract(world(Id, owned(_), Meta))
		   ->  assertz(world(Id, owned(S), Meta))
		   ;   true
		   )).

world_kind(Id, K) :- ( world(Id, owned(_), _) -> K = "owned" ; K = "live" ).

%       What an agent must be told before it can say anything: the world's
%       handle, where it is, the words it may speak, and the rules that will
%       refuse it. Everything else it can ask for.
world_overview(Id, S, _{world: Id, program: P, cycle: C, status: St, kind: K,
			vocabulary: _{events: EV, actions: AC, fluents: FL},
			constraints: CS, state: State}) :-
	( world(Id, _, Meta), get_dict(program, Meta, P0) -> P = P0 ; P = "" ),
	world_kind(Id, K),
	lps_session_time(S, C), status_text(S, St),
	lps_session_program(S, Prog),
	findall(T, ( declared_event(Prog, E), term_text(E, T) ), EV),
	findall(T, ( declared_action(Prog, A), term_text(A, T) ), AC),
	findall(T, ( p_user_fluent(Prog, F), term_text(F, T) ), FL),
	constraint_dicts(Prog, CS),
	lps_session_state(S, Fluents), terms_texts(Fluents, State).

status_text(S, T) :- lps_session_status(S, St), format(string(T), '~w', [St]).

declared_action(P, A) :-
	p_action(P, A), \+ p_system_action(P, A), \+ p_editing_action(P, A),
	\+ p_timeless(P, A).

declared_event(P, E) :-
	p_event(P, E), \+ p_system_action(P, E), \+ p_editing_action(P, E),
	\+ p_timeless(P, E), \+ declared_action(P, E).

declared_actions(S, As) :-
	lps_session_program(S, P),
	findall(A, declared_action(P, A), As).

%       A constraint, its English gloss and — when the compiler kept it — the
%       line of the program it was written on, so an agent can cite the rule
%       that refused it rather than paraphrase it.
constraint_dicts(P, CS) :-
	findall(D, ( p_d_pre(P, C), constraint_dict(P, C, D) ), CS).

constraint_dict(P, C, D) :-
	term_text(C, T),
	constraint_gloss(C, G),
	(   catch(p_term_src(P, d_pre(C), src(File, Line, _, _)), _, fail)
	->  file_base_name(File, Base),
	    format(string(Where), '~w:~w', [Base, Line]),
	    D = _{constraint: T, reads: G, at: Where}
	;   D = _{constraint: T, reads: G}
	).

%       `false A from T1 to T2, C1, C2` reads as "never A while C1 and C2".
constraint_gloss(Conds, G) :-
	copy_term(Conds, C), numbervars(C, 0, _),
	(   select(happens(A, _, _), C, Rest)
	->  ( Rest == []
	    -> format(string(G), 'never ~q', [A])
	    ;  conds_text(Rest, RT), format(string(G), 'never ~q while ~w', [A, RT]) )
	;   conds_text(C, CT), format(string(G), 'never: ~w', [CT])
	).

conds_text(Conds, Text) :-
	findall(T, ( member(X, Conds), cond_text(X, T) ), Ts),
	atomic_list_concat(Ts, ' and ', A), atom_string(A, Text).

cond_text(holds(F, _), T) :- !, format(atom(T), '~q', [F]).
cond_text(happens(E, _, _), T) :- !, format(atom(T), '~q happens', [E]).
cond_text(X, T) :- format(atom(T), '~q', [X]).

		 /*******************************
		 *         the guardrail        *
		 *******************************/

%!      refusals(+Session, +Action, -Refusals) is det.
%
%       Every integrity constraint that refuses Action in the state this
%       world is in, each as refusal(Instance, Constraint, Holding): the
%       action as the constraint binds it (so a pattern with variables comes
%       back with the instance that is refused), the constraint itself, and
%       the conditions of it that hold.
%
%       This is lps_play.pl's `refused_now/2`, generalised from one ground
%       action to a pattern and made to report what it found rather than
%       merely fail. It is one evaluation in the borrowed state — no cycle
%       runs, nothing is committed, and the session is not touched.
refusals(S, Action, Refusals) :-
	lps_session_program(S, P),
	lps_session_state(S, Fluents),
	lps_session_time(S, Now),
	install_session(S),
	Next is Now + 1,
	%  The goal is module-qualified on purpose: with_borrowed_state/3 is not
	%  a meta-predicate, so an unqualified goal would be called in
	%  lps_explain, where this module's imports — holds_all/1 above all —
	%  are not visible, and every constraint would quietly fail to apply.
	catch(lps_explain:with_borrowed_state(Fluents, Now,
		lps_mcp:refusal_search(P, Action, Now, Next, Rs)),
	      _, Rs = []),
	dedup_refusals(Rs, Refusals).

%!	refusal_search(+Program, +Action, +Now, +Next, -Refusals) is det.
%
%	Every constraint of the program with Action in its `happens` position
%	whose remaining conditions hold in the state borrowed by the caller.
refusal_search(P, Action, Now, Next, Rs) :-
	findall(refusal(Inst, C0, Holding),
		( p_d_pre(P, _, Conds0), copy_term(Conds0, C0),
		  copy_term(C0, C1),
		  select(happens(A, T1, T2), C1, Rest),
		  \+ A \= Action,
		  A = Action, T1 = Now, T2 = Next,
		  catch(holds_all(Rest), _, fail),
		  copy_term(A-Rest, Inst-Holding) ),
		Rs).

dedup_refusals(Rs, Out) :- foldl(add_refusal, Rs, [], R0), reverse(R0, Out).

add_refusal(R, Seen, Out) :-
	( member(S, Seen), variant(S, R) -> Out = Seen ; Out = [R|Seen] ).

%       The store the constraint is evaluated against belongs to this
%       session, and the program's module has to be the installed one, or an
%       intensional condition resolves against whatever ran last.
install_session(S) :-
	catch(( S = session(_, P, Opts, _, _, Store, _, _, _),
		lps_session:install(P, Opts),
		lps_store:store_load(Store) ), _, true).

refusal_dicts(S, Refusals, Ds) :-
	lps_session_program(S, P),
	findall(D, ( member(refusal(Inst, C, Holding), Refusals),
		     refusal_dict(P, Inst, C, Holding, D) ), Ds).

refusal_dict(P, Inst, C, Holding, D) :-
	constraint_dict(P, C, D0),
	term_text(Inst, IT),
	conds_text(Holding, HT),
	D = D0.put(_{refuses: IT, because: HT}).

why_not_lines(S, Action, Lines) :-
	lps_session_time(S, T),
	(   catch(lps_session_explain(S, why_not(happened(Action), T), E), _, fail),
	    E = explanation(_, Verdict, _),
	    Verdict \== no_goal_created,
	    explanation_text(E, L0)
	->  strings_of(L0, Lines)
	;   Lines = []
	).

may_dict(S, A, T, D) :-
	refusals(S, A, Rs),
	(   Rs == []
	->  D = _{action: T, permitted: true}
	;   findall(_{instance: IT, reads: G},
		    ( member(refusal(Inst, C, _), Rs),
		      term_text(Inst, IT), constraint_gloss(C, G) ), Rd),
	    (   ground(A)
	    ->  D = _{action: T, permitted: (false), refused_by: Rd}
	    ;   D = _{action: T, permitted: "some instances", refused_by: Rd}
	    )
	).

would_violate(S, A, T, N, D) :-
	refusals(S, A, Rs),
	(   Rs \== []
	->  findall(G, ( member(refusal(_, C, _), Rs), constraint_gloss(C, G) ), Gs),
	    D = _{candidate: T, outcome: "refused by a constraint", constraints: Gs}
	;   lps_session_time(S, T0),
	    (   catch(( lps_session_observe(S, [A], P1),
			lps_session_run(P1, cycles(N), P2, _) ), _, fail)
	    ->  violations(P2, T0, V),
		(   V == []
		->  D = _{candidate: T, outcome: "nothing breaks"}
		;   D = _{candidate: T, outcome: "leads to a violation", violations: V}
		)
	    ;   D = _{candidate: T, outcome: "could not be tried"}
	    )
	).

		 /*******************************
		 *        consequences          *
		 *******************************/

%!      consequences(+Before, +After, +From, -Dict) is det.
%
%       What the probe run did: the cycles it ran, what happened in each,
%       what the state gained and lost, and anything refused or violated.
consequences(S0, S2, From, _{cycles: _{from: From, to: To}, happened: H,
			     state_gained: Gained, state_lost: Lost,
			     refused: R, violations: V}) :-
	lps_session_time(S2, To),
	findall(_{cycle: C, items: Items},
		( between_cycles(From, S2, C), cycle_events(S2, C, Items), Items \== [] ),
		H),
	lps_session_state(S0, F0), lps_session_state(S2, F1),
	term_difference(F1, F0, Gained),
	term_difference(F0, F1, Lost),
	lps_session_refused(S2, Refused0),
	findall(D, ( member(refused(C, Es, Conds), Refused0), C >= From,
		     refused_dict(C, Es, Conds, D) ), R),
	violations(S2, From, V).

after_report(Id, S0, S2, T0, _Reports, Texts, Reply) :-
	consequences(S0, S2, T0, Cons),
	lps_session_time(S2, C), status_text(S2, St),
	( get_dict(refused, Cons, [_|_]) -> Accepted = (false) ; Accepted = true ),
	Reply = _{world: Id, observed: Texts, accepted: Accepted,
		  cycle: C, status: St, consequences: Cons}.

%!      violations(+Session, +From, -List) is det.
%
%       Two kinds, and an agent needs both: an observation an integrity
%       constraint refused as it arrived, and an action the engine would not
%       commit because a constraint held against it.
violations(S, From, V) :-
	lps_session_trace(S, Trace),
	findall(D,
		( member(R, Trace), violation_record(R, Kind, C, Conds), C >= From,
		  conds_text(Conds, CT),
		  D = _{kind: Kind, cycle: C, conditions: CT} ),
		V0),
	dedup_dicts(V0, V).

violation_record(observation_refused(T, _, Conds), "observation refused", C, Conds) :-
	C is T + 1.
violation_record(prospective_violation(T, Conds), "action refused", C, Conds) :-
	C is T + 1.

dedup_dicts(L, Out) :- foldl([X, In, O]>>( memberchk(X, In) -> O = In ; O = [X|In] ), L, [], R),
	reverse(R, Out).

refused_dicts(Refused, Ds) :-
	findall(_{cycle: C, events: ET, conditions: CT},
		( member(refused(C, Es, Conds), Refused),
		  terms_texts(Es, ET), conds_text(Conds, CT) ),
		Ds).

refused_dict(C, Es, Conds, _{cycle: C, events: ET, conditions: CT}) :-
	terms_texts(Es, ET), conds_text(Conds, CT).

		 /*******************************
		 *      running and reading     *
		 *******************************/

%       Step until the world goes quiet — no events, no composites, no
%       actions and no change of state — or until the cap. An agent that
%       said "the window opened" wants the consequences of that, not one
%       cycle of them.
settle(S0, S, Reports) :- settle_(S0, 12, S, Reports).

settle_(S, 0, S, []) :- !.
settle_(S0, N, S, Reports) :-
	(   lps_session_status(S0, running)
	->  lps_session_step(S0, S1, Report),
	    (   quiet_cycle(S1, Report)
	    ->  S = S1, Reports = []
	    ;   N1 is N - 1, settle_(S1, N1, S, Rest), Reports = [Report|Rest]
	    )
	;   S = S0, Reports = []
	).

quiet_cycle(S, cycle(T, Events, Composites, _, Actions)) :-
	Events == [], Composites == [], Actions == [],
	\+ cycle_changed(S, T).
quiet_cycle(_, none).

cycle_changed(S, T) :-
	catch(lps_session_changes(S, T, changes(_, I, Te, U, _)), _, fail),
	( I \== [] ; Te \== [] ; U \== [] ), !.

run_schedule(S0, Schedule, N, S) :- run_schedule_(0, N, Schedule, S0, S).

run_schedule_(I, N, _, S, S) :- I >= N, !.
run_schedule_(I, N, Sch, S0, S) :-
	findall(E, member(ev(I, E, _), Sch), Es),
	( Es == [] -> S1 = S0 ; catch(lps_session_observe(S0, Es, S1), _, S1 = S0) ),
	( lps_session_status(S1, running) -> catch(lps_session_step(S1, S2, _), _, S2 = S1) ; S2 = S1 ),
	I1 is I + 1,
	run_schedule_(I1, N, Sch, S2, S).

schedule(Args, Schedule) :-
	(   get_dict(events, Args, L), is_list(L)
	->  findall(ev(At, T, Text),
		    ( nth0(_, L, E), schedule_entry(E, At, T, Text) ), Schedule)
	;   Schedule = []
	).

schedule_entry(E, At, Term, Text) :-
	is_dict(E), !,
	( get_dict(event, E, S) -> true ; get_dict(term, E, S) ),
	( get_dict(after, E, At0), integer(At0) -> At = At0 ; At = 0 ),
	text_term(S, Term, Text).
schedule_entry(E, 0, Term, Text) :- text_term(E, Term, Text).

schedule_texts(Sch, Ts) :-
	findall(_{event: T, after: At}, member(ev(At, _, T), Sch), Ts).

between_cycles(From, S, C) :-
	lps_session_time(S, To),
	From =< To,
	between(From, To, C).

cycle_events(S, C, Texts) :-
	lps_session_trace(S, Trace),
	(   member(stage((events), C, Items), Trace)
	->  terms_texts(Items, Texts)
	;   Texts = []
	).

cycle_actions(S, P, C, Texts) :-
	lps_session_trace(S, Trace),
	(   member(stage((events), C, Items), Trace)
	->  findall(T, ( member(A, Items), \+ \+ declared_action(P, A), term_text(A, T) ), Texts)
	;   Texts = []
	).

state_at(S, At, Fluents) :-
	lps_session_trace(S, Trace),
	member(stage((fluents), At, Fluents), Trace), !.

first_stage_match(S, Stage, Pattern, Cycle, Item) :-
	lps_session_trace(S, Trace),
	findall(C, member(stage(Stage, C, _), Trace), Cs0),
	sort(Cs0, Cs),
	member(Cycle, Cs),
	member(stage(Stage, Cycle, Items), Trace),
	member(Item0, Items),
	\+ Item0 \= Pattern, !,
	Item = Item0.

timeline_dict(S, timeline(Max, FluentLanes, EventLane, CompositeLane),
	      _{cycles: Max, fluents: FL, events: EV, composites: CP, refused: RD}) :-
	findall(_{fluent: FT, intervals: IT},
		( member(lane(F, Is), FluentLanes), term_text(F, FT), term_text(Is, IT) ),
		FL),
	lane_dicts(EventLane, EV),
	lane_dicts(CompositeLane, CP),
	lps_session_refused(S, Refused),
	refused_dicts(Refused, RD).

lane_dicts(lane(_, Items), Ds) :-
	findall(D, ( member(I, Items), lane_dict(I, D) ), Ds0),
	append(Ds0, Ds).
lane_dicts(_, []).

%	A lane cell is `cell(Cycle, Items)`: one row per item, so an agent can
%	read "window(open) at cycle 3" without unpacking a list of lists.
lane_dict(cell(C, Items), Ds) :- !,
	findall(_{cycle: C, item: T}, ( member(X, Items), term_text(X, T) ), Ds).
lane_dict(at(C, X), [_{cycle: C, item: T}]) :- !, term_text(X, T).
lane_dict(C-X, [_{cycle: C, item: T}]) :- integer(C), !, term_text(X, T).
lane_dict(X, [_{item: T}]) :- term_text(X, T).

change_dict(change(F, A, Src, _), D) :- !,
	cause_text(A, AT),
	source_text(Src, ST),
	(   nonvar(F), F = Old-New
	->  term_text(Old, OT), term_text(New, NT),
	    format(string(FT), '~w -> ~w', [OT, NT]),
	    D = _{fluent: NT, was: OT, became: NT, change: FT, by: AT, law: ST}
	;   term_text(F, FT),
	    D = _{fluent: FT, by: AT, law: ST}
	).
change_dict(X, _{change: T}) :- term_text(X, T).

%	`happens(window(open), 2, 3)` is the engine's way of saying it; an
%	agent wants the event and the cycle it arrived in.
cause_text(A, T) :-
	(   nonvar(A), A = happens(E, _, T2), integer(T2)
	->  term_text(E, ET), format(string(T), '~w at cycle ~w', [ET, T2])
	;   nonvar(A), A = happens(E, _, _)
	->  term_text(E, T)
	;   term_text(A, T)
	).

source_text(Src, T) :-
	(   nonvar(Src), Src = src(File, Line, _, _)
	->  file_base_name(File, Base), format(string(T), '~w:~w', [Base, Line])
	;   term_text(Src, T)
	).

question_term(Args, S, Q, QText) :-
	(   arg_text_opt(Args, question, QS)
	->  parse_term_string(QS, Q), term_text(Q, QText)
	;   arg_text_opt(Args, kind, K0), arg_text_opt(Args, what, W0)
	->  parse_term_string(W0, W),
	    ( arg_int_opt(Args, at, At) -> true ; lps_session_time(S, At) ),
	    atom_string(KA, K0),
	    Q =.. [KA, W, At],
	    term_text(Q, QText)
	).

outstanding(S, Out) :-
	(   catch(lps_session_goals(S, Goals), _, fail)
	->  true
	;   Goals = []
	),
	findall(_{id: I, owed: T}, ( member(G, Goals), goal_text(G, I, T) ), Out).

goal_text(G, I, T) :-
	G = goal(ID, _, _, _, _, _, Cont), !,
	format(string(I), '~w', [ID]),
	copy_term(Cont, C), numbervars(C, 0, _),
	format(string(T), '~q', [C]).
goal_text(G, "", T) :- term_text(G, T).

		 /*******************************
		 *      programs and files      *
		 *******************************/

%       The example catalogue belongs to the IDE server (lps_http), which
%       knows about converted sources and directory labels. It is reached by
%       late binding rather than by import: the HTTP module is a client of
%       this one, and a server started without it still runs from paths.
shipped_program(Name, Title) :-
	current_predicate(lps_http:example_list/1),
	lps_http:example_list(Es),
	member(E, Es),
	get_dict(name, E, Name0), atom_string(Name0, Name),
	( get_dict(title, E, T0) -> atom_string(T0, Title) ; Title = "" ).

load_program(Args, Program, Name, Diags) :-
	(   arg_text_opt(Args, source, Src)
	->  arg_text(Args, syntax, lps, Syn0),
	    syntax_name(Syn0, Syn),
	    Name = "buffer",
	    compile_text(Syn, Src, Program0, Diags0),
	    %  Program text in a request comes from a stranger, whatever the
	    %  transport: this door has the HTTP endpoint's policy, not the
	    %  CLI's (src/edges/lps_sandbox.pl says why they differ). A program
	    %  the server itself ships is not checked, for the same reason the
	    %  CLI does not check your own file.
	    sandboxed(Program0, Diags0, Program, Diags)
	;   arg_text_opt(Args, program, Spec0), Spec0 \== ''
	->  atom_string(Spec, Spec0),
	    (   resolve_program_file(Spec, Path)
	    ->  atom_string(Spec, Name),
		compile_file_any(Path, Program, Diags)
	    ;   format(atom(M), 'no program ~w — call list_programs', [Spec]),
		throw(error(mcp_error(M), _))
	    )
	;   throw(error(mcp_error('give `program` (a name from list_programs) or `source`'), _))
	).

sandboxed(none, Diags, none, Diags) :- !.
sandboxed(Program, Diags0, Program1, Diags) :-
	(   sandbox_enabled([default(server)], true)
	->  catch(sandbox_check(Program, SDiags), _, SDiags = [])
	;   SDiags = []
	),
	append(Diags0, SDiags, Diags),
	( diags_ok(Diags) -> Program1 = Program ; Program1 = none ).

syntax_name(S, Syn) :-
	atom_string(A, S),
	( memberchk(A, [lps, legacy, surface]) -> Syn = legacy
	; memberchk(A, [internal, 'P']) -> Syn = internal
	; A == le -> Syn = le
	; Syn = legacy ).

compile_text(le, Src, Program, Diags) :- !,
	lps_le:lps_le_translate_text(Src, 'buffer.le', Text, Prov, LeDiags),
	(   diags_ok(LeDiags), Text \== ""
	->  lps_le:lps_le_program_terms(Text, 'buffer.le', Prov, "", '', Terms, ReadDiags),
	    lps_compile(terms(Terms), internal, [dc], Program, CDiags),
	    append([LeDiags, ReadDiags, CDiags], Diags)
	;   Program = none, Diags = LeDiags
	).
compile_text(Syntax, Src, Program, Diags) :-
	lps_read_terms_string(Src, buffer, Terms, ReadDiags),
	(   diags_ok(ReadDiags)
	->  lps_compile(terms(Terms), Syntax, [dc], Program, CDiags),
	    append(ReadDiags, CDiags, Diags)
	;   Program = none, Diags = ReadDiags
	).

%       One rule for what a file is, shared with the CLI (lps_cli.pl's
%       syntax_of/3 and compile_with/5) rather than copied: the Logical
%       English companion rule lives there and must not be written twice.
compile_file_any(Path, Program, Diags) :-
	lps_cli:syntax_of(Path, [], Syntax),
	catch(lps_cli:compile_with(Syntax, Path, [dc], Program, Diags),
	      E, ( Program = none, error_diag(E, Diags) )).

error_diag(E, [D]) :-
	format(atom(M), '~q', [E]),
	diag(error, compile_failed, unknown, M, D).

resolve_program_file(Spec, Path) :- exists_file(Spec), !, Path = Spec.
resolve_program_file(Spec, Path) :-
	current_predicate(lps_http:example_path/2),
	lps_http:example_path(Spec, P), exists_file(P), !, Path = P.
resolve_program_file(Spec, Path) :-
	lps_root_dir(Root),
	atomic_list_concat([Root, '/', Spec], P), exists_file(P), !, Path = P.

lps_root_dir(Dir) :-
	(   current_predicate(lps_le:lps2_root/1), lps_le:lps2_root(D)
	->  Dir = D
	;   working_directory(Dir, Dir)
	).

%	The live registry has no listing of its own; this reads its one dynamic
%	rather than duplicating a registry of running sessions.
live_ids(Id) :- lps_live:live(Id, _).

		 /*******************************
		 *          arguments           *
		 *******************************/

arg_text(Args, Key, Default, Value) :-
	(   get_dict(Key, Args, V), V \== null
	->  ( number(V) -> atom_number(A, V), Value = A ; atom_string(Value, V) )
	;   Value = Default
	).

arg_text_opt(Args, Key, Value) :-
	get_dict(Key, Args, V), V \== null, atom_string(Value, V), Value \== ''.

arg_int(Args, Key, Default, N) :-
	( get_dict(Key, Args, V), integer(V) -> N = V ; N = Default ).

arg_int_opt(Args, Key, N) :- get_dict(Key, Args, V), integer(V), N = V.

arg_term(Args, Key, Term, Text) :-
	(   get_dict(Key, Args, V)
	->  text_term(V, Term, Text)
	;   format(atom(M), 'this tool needs `~w`', [Key]),
	    throw(error(mcp_error(M), _))
	).

arg_term_opt(Args, Key, Term, Text) :-
	get_dict(Key, Args, V), V \== null, text_term(V, Term, Text).

arg_terms(Args, Key, Terms, Texts) :-
	(   get_dict(Key, Args, L), is_list(L)
	->  findall(T-X, ( member(E, L), text_term(E, T, X) ), Pairs),
	    pairs_keys_values(Pairs, Terms, Texts)
	;   format(atom(M), 'this tool needs `~w`, an array of terms', [Key]),
	    throw(error(mcp_error(M), _))
	).

arg_terms_opt(Args, Key, Terms, Texts) :-
	get_dict(Key, Args, L), is_list(L), L \== [],
	findall(T-X, ( member(E, L), text_term(E, T, X) ), Pairs),
	pairs_keys_values(Pairs, Terms, Texts).

%       A term arrives as text, and bad text is the ordinary case — an agent
%       guessing at a functor. Say which text failed rather than throwing a
%       syntax error at the protocol.
text_term(V, Term, Text) :-
	(   atom_string(S, V)
	->  true
	;   format(atom(S), '~w', [V])
	),
	(   catch(parse_term_string(S, Term), _, fail)
	->  atom_string(S, Text)
	;   format(atom(M), 'not a term: ~w', [S]),
	    throw(error(mcp_error(M), _))
	).

parse_term_string(S, T) :-
	current_prolog_flag(allow_dot_in_atom, Old),
	setup_call_cleanup(set_prolog_flag(allow_dot_in_atom, true),
			   term_string(T, S),
			   set_prolog_flag(allow_dot_in_atom, Old)).

		 /*******************************
		 *            text              *
		 *******************************/

term_text(T, S) :-
	copy_term(T, C), numbervars(C, 0, _),
	format(string(S), '~q', [C]).

terms_texts(Ts, Ss) :- findall(S, ( member(T, Ts), term_text(T, S) ), Ss).

strings_of(L, Ss) :- findall(S, ( member(X, L), format(string(S), '~w', [X]) ), Ss).

diag_texts(Diags, Ts) :-
	findall(S, ( member(D, Diags), format_diag(D, A), atom_string(A, S) ), Ts).

filter_terms(Ts, '', Ts) :- !.
filter_terms(Ts, Match, Kept) :-
	findall(T, ( member(T, Ts), term_text(T, S), matches_text(S, Match) ), Kept).

matches_text(S, Match) :-
	atom_string(A, S), atom_string(M, Match),
	downcase_atom(A, LA), downcase_atom(M, LM),
	sub_atom(LA, _, _, _, LM).

term_difference(As, Bs, Texts) :-
	findall(T, ( member(A, As), \+ ( member(B, Bs), variant(A, B) ), term_text(A, T) ), Texts).

pairs_upto(Terms, Texts, Limit, Pairs) :-
	pairs_keys_values(All, Terms, Texts),
	length(All, N),
	( N =< Limit -> Pairs = All ; length(Pairs, Limit), append(Pairs, _, All) ).
