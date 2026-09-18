/* mcp_test.pl — the Model Context Protocol surface (src/edges/lps_mcp.pl).

	./myswipl.sh -q -g "consult('tools/mcp_test.pl')" -g "mcp_test:main" -t halt

   What is actually being checked is the property the whole surface exists for:
   an agent asking "may I?" gets the same answer the engine would give if it
   tried, and asking costs the world nothing. Everything else — the envelope,
   the handles, the readings — is in support of that, and is checked because a
   tool an agent cannot parse is a tool it will not use.

   With a Logical English checkout (LPS_LE2_LIB) two more cases run, on an
   LE-for-LPS program; without one they are skipped and say so.
*/

:- module(mcp_test, [main/0]).

:- use_module('../src/lps').
:- use_module('../src/edges/lps_mcp').
:- use_module('../src/edges/lps_le', [lps_le_available/1]).
:- use_module('../src/core/lps_session').
:- use_module(library(lists)).
:- use_module(library(http/json)).

:- dynamic failures/1, skipped/1.
failures(0).
skipped(0).

main :-
	retractall(failures(_)), assertz(failures(0)),
	retractall(skipped(_)), assertz(skipped(0)),
	forall(section(S), run_section(S)),
	failures(N), skipped(K),
	(   N =:= 0
	->  format('~n=== mcp: every case behaves (~w skipped) ===~n', [K])
	;   format('~n=== mcp: ~w FAILED ===~n', [N]), halt(1)
	).

section(protocol).
section(worlds).
section(guardrail).
section(lookahead).
section(reading).
section(errors).
section(live).
section(logical_english).

run_section(S) :-
	format('~n~w~n', [S]),
	forall(case(S, What, Goal), run_case(What, Goal)).

run_case(What, Goal) :-
	(   catch(call(Goal), E, ( format('  FAIL  ~w~t~58|threw ~q~n', [What, E]), fail ))
	->  format('  ok    ~w~n', [What])
	;   format('  FAIL  ~w~n', [What]),
	    retract(failures(N)), N1 is N + 1, assertz(failures(N1))
	).

skip(Why) :- format('  skip  ~w~n', [Why]),
	retract(skipped(N)), N1 is N + 1, assertz(skipped(N1)).

		 /*******************************
		 *          the cases           *
		 *******************************/

case(protocol, 'initialize names the protocol and the server', mcp_test:t_initialize).
case(protocol, 'tools/list offers every tool with a schema', mcp_test:t_tools_list).
case(protocol, 'tools/call answers one text item of JSON', mcp_test:t_tools_call).
case(protocol, 'an unknown method is -32601, not a crash', mcp_test:t_unknown_method).
case(protocol, 'prompts and resources are listed', mcp_test:t_prompts_resources).

case(worlds, 'open_world gives a handle, a vocabulary and the constraints', mcp_test:t_open).
case(worlds, 'list_worlds finds it, close_world forgets it', mcp_test:t_list_close).
case(worlds, 'observe advances the world and says what changed', mcp_test:t_observe).
case(worlds, 'state reads a past cycle as well as the present', mcp_test:t_state_at).

case(guardrail, 'an action the constraints allow is permitted', mcp_test:t_permitted).
case(guardrail, 'an action a constraint forbids is refused, and the constraint is named',
     mcp_test:t_refused).
case(guardrail, 'asking does not advance the world', mcp_test:t_probe_is_free).
case(guardrail, 'may reports the refused instance of a pattern', mcp_test:t_may).
case(guardrail, 'the guardrail agrees with the engine', mcp_test:t_agrees_with_engine).

case(lookahead, 'simulate runs on a copy and leaves the world where it was', mcp_test:t_simulate).
case(lookahead, 'what_would_violate separates what breaks from what does not',
     mcp_test:t_what_would_violate).
case(lookahead, 'plan says what the world will do next', mcp_test:t_plan).

case(reading, 'timeline carries the cycles and the fluent lanes', mcp_test:t_timeline).
case(reading, 'changes names the event that caused each change', mcp_test:t_changes).
case(reading, 'explain answers a why question in English', mcp_test:t_explain).
case(reading, 'find_first finds the cycle something started at', mcp_test:t_find_first).
case(reading, 'obligations answers, and is a list', mcp_test:t_obligations).

case(errors, 'an unknown world says so', mcp_test:t_no_world).
case(errors, 'text that is not a term says which text', mcp_test:t_bad_term).
case(errors, 'an unknown tool is an error, not a failure', mcp_test:t_unknown_tool).
case(errors, 'a program that does not compile reports its diagnostics', mcp_test:t_bad_program).
case(errors, 'a program from a request that reaches the machine is refused', mcp_test:t_sandbox).

case(live, 'a live session can be attached, read and stopped', mcp_test:t_live).

case(logical_english, 'an LE-for-LPS program opens with its own vocabulary', mcp_test:t_le_open).
case(logical_english, 'its constraints refuse what the contract forbids', mcp_test:t_le_guardrail).

		 /*******************************
		 *          protocol            *
		 *******************************/

t_initialize :-
	mcp_message(_{jsonrpc: "2.0", id: 1, method: "initialize", params: _{}}, R),
	get_dict(result, R, Res),
	get_dict(protocolVersion, Res, "2024-11-05"),
	get_dict(serverInfo, Res, SI), get_dict(name, SI, "LPS2 MCP Server").

t_tools_list :-
	mcp_message(_{jsonrpc: "2.0", id: 2, method: "tools/list"}, R),
	get_dict(result, R, Res), get_dict(tools, Res, Tools),
	length(Tools, N), N >= 15,
	forall(member(T, Tools),
	       ( get_dict(name, T, Name), Name \== "",
		 get_dict(description, T, D), string_length(D, DL), DL > 20,
		 get_dict(inputSchema, T, S), get_dict(type, S, "object") )),
	memberchk_name(Tools, "propose_action"),
	memberchk_name(Tools, "simulate"),
	memberchk_name(Tools, "explain").

memberchk_name(Tools, Name) :- member(T, Tools), get_dict(name, T, Name), !.

t_tools_call :-
	mcp_message(_{jsonrpc: "2.0", id: 3, method: "tools/call",
		      params: _{name: "list_programs", arguments: _{match: "thermostat"}}}, R),
	get_dict(result, R, Res),
	get_dict(isError, Res, false),
	get_dict(content, Res, [Item|_]),
	get_dict(type, Item, "text"),
	get_dict(text, Item, Text),
	atom_json_dict(Text, Dict, []),
	get_dict(programs, Dict, [P|_]),
	get_dict(name, P, "start/thermostat").

t_unknown_method :-
	mcp_message(_{jsonrpc: "2.0", id: 4, method: "no/such"}, R),
	get_dict(error, R, E), get_dict(code, E, -32601).

t_prompts_resources :-
	mcp_message(_{jsonrpc: "2.0", id: 5, method: "prompts/list"}, R1),
	get_dict(result, R1, P1), get_dict(prompts, P1, Ps), Ps \== [],
	mcp_message(_{jsonrpc: "2.0", id: 6, method: "resources/list"}, R2),
	get_dict(result, R2, P2), get_dict(resources, P2, Rs), Rs \== [].

		 /*******************************
		 *           worlds             *
		 *******************************/

thermostat(W) :-
	mcp_call_tool("open_world", _{program: "start/thermostat", run: 1}, R),
	get_dict(world, R, W).

%       The window open, which is the state the constraint speaks about.
thermostat_open_window(W) :-
	thermostat(W),
	mcp_call_tool("observe", _{world: W, events: ["window(open)"]}, _).

t_open :-
	mcp_call_tool("open_world", _{program: "start/thermostat", run: 1}, R),
	get_dict(world, R, W), W \== "",
	get_dict(status, R, "running"),
	get_dict(vocabulary, R, V),
	get_dict(actions, V, As), memberchk("heat(A)", As),
	get_dict(events, V, Es), memberchk("window(A)", Es),
	get_dict(constraints, R, [C|_]),
	get_dict(reads, C, Reads), sub_string(Reads, _, _, _, "never heat(on)"),
	get_dict(at, C, At), sub_string(At, _, _, _, "thermostat.lps:"),
	get_dict(state, R, St), memberchk("window_state(shut)", St).

t_list_close :-
	thermostat(W),
	mcp_call_tool("list_worlds", _{}, R), get_dict(worlds, R, Ws),
	member(X, Ws), get_dict(world, X, W), !,
	mcp_call_tool("close_world", _{world: W}, C), get_dict(closed, C, true),
	mcp_call_tool("state", _{world: W}, E), get_dict(error, E, _).

t_observe :-
	thermostat(W),
	mcp_call_tool("observe", _{world: W, events: ["window(open)"]}, R),
	get_dict(accepted, R, true),
	get_dict(consequences, R, C),
	get_dict(state_gained, C, G), memberchk("window_state(open)", G),
	get_dict(state_lost, C, L), memberchk("window_state(shut)", L),
	mcp_call_tool("state", _{world: W, match: "window"}, S),
	get_dict(fluents, S, ["window_state(open)"]).

t_state_at :-
	thermostat_open_window(W),
	mcp_call_tool("state", _{world: W, at: 1, match: "window"}, R),
	get_dict(fluents, R, ["window_state(shut)"]).

		 /*******************************
		 *          guardrail           *
		 *******************************/

t_permitted :-
	thermostat(W),
	mcp_call_tool("propose_action", _{world: W, action: "heat(on)"}, R),
	get_dict(permitted, R, true),
	get_dict(consequences, R, C), get_dict(state_gained, C, G),
	memberchk("heating(on)", G).

t_refused :-
	thermostat_open_window(W),
	mcp_call_tool("propose_action", _{world: W, action: "heat(on)"}, R),
	get_dict(permitted, R, false),
	get_dict(refused_by, R, [C|_]),
	get_dict(reads, C, Reads), sub_string(Reads, _, _, _, "never heat(on)"),
	get_dict(because, C, B), sub_string(B, _, _, _, "window_state(open)"),
	get_dict(refuses, C, "heat(on)").

t_probe_is_free :-
	thermostat_open_window(W),
	mcp_call_tool("world_status", _{world: W}, B), get_dict(cycle, B, C0),
	mcp_call_tool("propose_action", _{world: W, action: "heat(on)"}, _),
	mcp_call_tool("propose_action", _{world: W, action: "heat(off)"}, _),
	mcp_call_tool("simulate", _{world: W, events: ["window(shut)"], cycles: 4}, _),
	mcp_call_tool("world_status", _{world: W}, A), get_dict(cycle, A, C1),
	C0 == C1.

t_may :-
	thermostat_open_window(W),
	mcp_call_tool("may", _{world: W}, R),
	get_dict(actions, R, As),
	member(H, As), get_dict(action, H, "heat(A)"), !,
	get_dict(permitted, H, "some instances"),
	get_dict(refused_by, H, [I|_]), get_dict(instance, I, "heat(on)"),
	member(Warn, As), get_dict(action, Warn, "warn(A)"), !,
	get_dict(permitted, Warn, true).

%       The claim the whole surface stands on: what propose_action says about
%       an action is what the engine does with it. Ask, then actually observe
%       it, and see that the world agrees.
t_agrees_with_engine :-
	thermostat_open_window(W),
	mcp_call_tool("propose_action", _{world: W, action: "heat(on)"}, P),
	get_dict(permitted, P, false),
	mcp_call_tool("observe", _{world: W, events: ["heat(on)"], cycles: 2}, O),
	get_dict(accepted, O, false),
	get_dict(consequences, O, C), get_dict(refused, C, [_|_]),
	mcp_call_tool("state", _{world: W, match: "heating"}, S),
	get_dict(fluents, S, ["heating(off)"]).

		 /*******************************
		 *          lookahead           *
		 *******************************/

t_simulate :-
	thermostat(W),
	mcp_call_tool("world_status", _{world: W}, B), get_dict(cycle, B, C0),
	mcp_call_tool("simulate", _{world: W,
				    events: [_{event: "window(open)"},
					     _{event: "heat(on)", after: 2}],
				    cycles: 6}, R),
	get_dict(final_state, R, F), memberchk("window_state(open)", F),
	get_dict(consequences, R, C), get_dict(violations, C, [V|_]),
	get_dict(kind, V, "observation refused"),
	mcp_call_tool("world_status", _{world: W}, A), get_dict(cycle, A, C0).

t_what_would_violate :-
	thermostat_open_window(W),
	mcp_call_tool("what_would_violate",
		      _{world: W, candidates: ["heat(on)", "heat(off)"], cycles: 3}, R),
	get_dict(tested, R, Ts),
	member(On, Ts), get_dict(candidate, On, "heat(on)"), !,
	get_dict(outcome, On, "refused by a constraint"),
	member(Off, Ts), get_dict(candidate, Off, "heat(off)"), !,
	get_dict(outcome, Off, "nothing breaks"),
	get_dict(breaking, R, [B|_]), get_dict(candidate, B, "heat(on)").

t_plan :-
	thermostat(W),
	mcp_call_tool("observe", _{world: W, events: ["temperature(10)"], cycles: 0}, _),
	mcp_call_tool("plan", _{world: W, cycles: 4}, R),
	get_dict(steps, R, Steps),
	member(S, Steps), get_dict(actions, S, As), memberchk("heat(on)", As), !,
	mcp_call_tool("world_status", _{world: W}, A), get_dict(cycle, A, 2).

		 /*******************************
		 *           reading            *
		 *******************************/

t_timeline :-
	thermostat_open_window(W),
	mcp_call_tool("timeline", _{world: W}, R),
	get_dict(cycles, R, N), N >= 2,
	get_dict(fluents, R, Fs), Fs \== [],
	member(F, Fs), get_dict(fluent, F, "window_state(open)"), !,
	get_dict(intervals, F, I), sub_string(I, _, _, _, "interval("),
	get_dict(events, R, Evs),
	member(E, Evs), get_dict(item, E, "window(open)"), !.

t_changes :-
	thermostat_open_window(W),
	mcp_call_tool("timeline", _{world: W}, _),
	between(1, 6, C),
	mcp_call_tool("changes", _{world: W, cycle: C}, R),
	get_dict(updated, R, [U|_]),
	get_dict(fluent, U, "window_state(open)"),
	get_dict(was, U, "window_state(shut)"),
	get_dict(by, U, By), sub_string(By, _, _, _, "window(open)"),
	get_dict(law, U, Law), sub_string(Law, _, _, _, "thermostat.lps:"), !.

t_explain :-
	thermostat_open_window(W),
	mcp_call_tool("explain", _{world: W, kind: "why", what: "holds(window_state(open))"}, R),
	get_dict(verdict, R, V), V \== "",
	get_dict(explanation, R, Lines), Lines \== [],
	atomic_list_concat(Lines, ' ', All),
	sub_atom(All, _, _, _, 'window').

t_find_first :-
	thermostat_open_window(W),
	mcp_call_tool("find_first", _{world: W, holds: "window_state(open)"}, R),
	get_dict(found, R, true), get_dict(cycle, R, C), C >= 1,
	mcp_call_tool("find_first", _{world: W, holds: "window_state(ajar)"}, R2),
	get_dict(found, R2, false).

t_obligations :-
	thermostat_open_window(W),
	mcp_call_tool("obligations", _{world: W}, R),
	get_dict(outstanding, R, L), is_list(L),
	get_dict(count, R, N), integer(N).

		 /*******************************
		 *           errors             *
		 *******************************/

t_no_world :-
	mcp_call_tool("state", _{world: "world-nope"}, R),
	get_dict(error, R, M), sub_string(M, _, _, _, "no world").

t_bad_term :-
	thermostat(W),
	mcp_call_tool("propose_action", _{world: W, action: "heat("}, R),
	get_dict(error, R, M), sub_string(M, _, _, _, "not a term").

t_unknown_tool :-
	mcp_call_tool("fly_to_the_moon", _{}, R),
	get_dict(error, R, _).

t_bad_program :-
	mcp_call_tool("open_world", _{source: "fluents f(_). if then .", syntax: "lps"}, R),
	get_dict(error, R, _).

%	The same policy the HTTP endpoint has, on the same grounds: text in a
%	request is a stranger's, and this door takes text.
t_sandbox :-
	setup_call_cleanup(
	    setenv('LPS_SANDBOX', '1'),
	    ( mcp_call_tool("open_world",
			    _{source: "fluents f(_).\nactions go.\nmaxTime(3).\nescape :- shell('id').",
			      syntax: "lps"}, R),
	      get_dict(error, R, _),
	      get_dict(diagnostics, R, Ds), Ds \== [] ),
	    unsetenv('LPS_SANDBOX')).

		 /*******************************
		 *            live              *
		 *******************************/

t_live :-
	lps_compile(file('examples/start/thermostat.lps'), legacy, [dc], P, _),
	lps_live:live_start(P, [cycle_ms(200)], Id),
	setup_call_cleanup(
	    true,
	    ( mcp_call_tool("list_live", _{}, L),
	      get_dict(live, L, Ls), member(X, Ls), get_dict(live, X, Id), !,
	      mcp_call_tool("attach_live", _{live: Id}, A),
	      get_dict(world, A, W), get_dict(kind, A, "live"),
	      mcp_call_tool("state", _{world: W}, S),
	      get_dict(fluents, S, Fl), memberchk("target(21)", Fl),
	      mcp_call_tool("propose_action", _{world: W, action: "heat(on)"}, Pr),
	      get_dict(permitted, Pr, _) ),
	    lps_live:live_command(Id, stop)).

		 /*******************************
		 *      Logical English         *
		 *******************************/

le_world(W) :-
	lps_le_available(How), How \== none,
	mcp_call_tool("open_world", _{program: "le/bank_transfer", run: 1}, R),
	get_dict(world, R, W).

t_le_open :-
	(   lps_le_available(How), How \== none
	->  mcp_call_tool("open_world", _{program: "le/bank_transfer", run: 1}, R),
	    (   get_dict(error, R, E)
	    ->  format('  (~w)~n', [E]), fail
	    ;   get_dict(vocabulary, R, V), get_dict(actions, V, As),
		member(A, As), sub_string(A, _, _, _, "transfer"), !,
		get_dict(constraints, R, Cs), Cs \== []
	    )
	;   skip('no Logical English checkout (LPS_LE2_LIB)')
	).

t_le_guardrail :-
	(   le_world(W)
	->  mcp_call_tool("propose_action",
			  _{world: W, action: "transfer(fariba, 500, bob)"}, R),
	    get_dict(permitted, R, false),
	    get_dict(refused_by, R, [C|_]),
	    get_dict(at, C, At), sub_string(At, _, _, _, "bank_transfer.le:"),
	    get_dict(because, C, B), sub_string(B, _, _, _, "balance(fariba,"),
	    mcp_call_tool("propose_action",
			  _{world: W, action: "transfer(fariba, 50, bob)"}, R2),
	    get_dict(permitted, R2, true)
	;   skip('no Logical English checkout (LPS_LE2_LIB)')
	).
