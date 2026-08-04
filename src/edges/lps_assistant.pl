/* lps_assistant.pl — the LPS Assistant (M16, §I.10.6).
 *
 * A bounded agentic loop that owns a conversation and a tool-calling cycle,
 * modelled on LE2's "light" assistant (docs/le_assistant_light.md): Prolog
 * drives the model directly, tools are direct predicate calls in the same
 * process, and the program under discussion is a string threaded through the
 * loop rather than a file on disk. No subprocess, no MCP loopback, no
 * temporary directory.
 *
 * What differs from LE2's, and it is the whole content of this module: the
 * tools and the prompt. Where LE2 offers `verify` and `query` over a knowledge
 * base, we offer the three things the panes already do —
 *
 *     analyse   compile the program, return the diagnostics
 *     run       run it, return the trace summary
 *     explain   ask a why / why_not question of a run
 *
 * — so the model sees exactly what the editor's own buttons would show it.
 * That single source of truth is the point: an assistant whose idea of "this
 * compiles" differs from the IDE's is worse than none.
 *
 * This is an *edge*: it opens sockets, spawns threads for jobs and reads
 * files. None of it is reachable from src/core/.
 */

:- module(lps_assistant, [
	assistant_models/1,        % -List of dicts
	assistant_start/2,         % +Request, -JobId
	assistant_status/2,        % +JobId, -Status
	assistant_interrupt/1,     % +JobId
	assistant_translate/4      % +Program, +Text, +Opts, -Events
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(strings)).
:- use_module(library(http/json)).
:- use_module('../core/lps_diag').
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../core/lps_explain').
:- use_module(lps_llm).
:- use_module(lps_scene).

:- dynamic job/2.              % Id, Dict of state
:- dynamic job_counter/1.
job_counter(0).

/*  How many model calls one request may take.
 *
 *  It was 8, and 8 is not enough for the loop the prompts actually ask for:
 *  analyse, edit, analyse, run, scene, edit, analyse, scene, finish is nine
 *  before anything goes wrong. A user asking for one timeless predicate with
 *  four names got "I reached my step limit before finishing" — a budget
 *  failure reported as if it were a difficulty. The ceiling is here to stop a
 *  loop, not to ration work, so it belongs well above the honest case. */
max_steps(24).

		 /*******************************
		 *	     models		*
		 *******************************/

/* A model is offered only if a key for its provider can be found — in the
   server's environment first, then in whatever the browser sent. Listing a
   model the user cannot call is a worse experience than a short list.
*/
assistant_models(Models) :-
	assistant_models(_{}, Models).

/*  Ask the providers, and fall back to the table.
 *
 *  `lps_llm.pl`'s model table is maintained by hand and copied from LE2, so it
 *  is a list of names that were true when someone last edited it. lps_models.pl
 *  reads each provider's own catalogue at server start; this merges the two,
 *  discovered names winning, so the picker is right when the network works and
 *  non-empty when it does not.
 */
assistant_models(Keys, Models) :-
	catch(lps_models:models_available(Keys, Models0), _, fail),
	Models0 \== [], !,
	Models = Models0.
assistant_models(Keys, Models) :-
	findall(_{name: NameS, provider: ProvS, source: "builtin"},
		( llm_list_models(Rows), member(row(Name, Prov, _), Rows),
		  have_key(Prov, Keys, _),
		  atom_string(Name, NameS), atom_string(Prov, ProvS) ),
		Models0),
	sort(Models0, Models).

%!	have_key(+Provider, +Keys, -Key) is semidet.
%
%	Precedence, and it is the rule LE2 uses: **the server's environment
%	wins**. A deployment that configures a key centrally is not overridden
%	by whatever a browser happens to be carrying.
have_key(Provider, _Keys, Key) :-
	catch(lps_llm:api_key(Provider, Key), _, fail), !.
have_key(Provider, Keys, Key) :-
	is_dict(Keys),
	%  JSON dict keys arrive as atoms, so the provider name is the key as it
	%  stands; converting it to a string first is a type error.
	get_dict(Provider, Keys, K),
	K \== "", K \== null,
	atom_string(Key, K).

		 /*******************************
		 *	      jobs		*
		 *******************************/

/* The job model is LE2's, because the editor's polling loop is: start returns
   an id, status returns `running` plus a progress tail or a final answer, and
   interrupt sets a flag the loop checks before each model call. Cooperative,
   not pre-emptive — a request already in flight finishes.
*/
assistant_start(Req, Id) :-
	retract(job_counter(N)), N1 is N + 1, assertz(job_counter(N1)),
	format(atom(Id), 'job~w', [N1]),
	assertz(job(Id, _{status: running, output: [], explanation: "",
			  new_content: null, error: null, interrupt: false})),
	thread_create(run_job(Id, Req), _, [detached(true)]).

assistant_status(Id, Status) :-
	Empty = _{status: "unknown", output: [], explanation: "",
		  new_content: null, error: null, interrupt: false},
	(   job(Id, S)
	->  Status = Empty.put(S)
	;   Status = Empty.put(error, "no such job")
	).

assistant_interrupt(Id) :-
	( job(Id, S) -> update_job(Id, S.put(interrupt, true)) ; true ).

update_job(Id, S) :- retractall(job(Id, _)), assertz(job(Id, S)).

progress(Id, Line) :-
	(   job(Id, S)
	->  append(S.output, [Line], Out),
	    update_job(Id, S.put(output, Out))
	;   true
	).

interrupted(Id) :- job(Id, S), S.interrupt == true.

run_job(Id, Req) :-
	catch(run_job_(Id, Req), E,
	      ( message_to_text(E, M),
		( job(Id, S) -> update_job(Id, S.put(_{status: "error", error: M})) ; true ) )).

run_job_(Id, Req) :-
	get_dict(command, Req, Command0),
	( get_dict(content, Req, Content) -> true ; Content = "" ),
	( get_dict(api_keys, Req, Keys) -> true ; Keys = _{} ),
	( get_dict(model, Req, M), M \== null -> Model = M ; default_model(Keys, Model) ),
	resolve_command(Command0, Command, Extra),
	system_prompt(Content, Extra, Req, System),
	Messages = [role(system, System), role(user, Command)],
	progress(Id, "thinking…"),
	agent_loop(Id, Model, Keys, Messages, Content, 0, Expl, Final),
	( job(Id, S) -> true ; S = _{} ),
	update_job(Id, S.put(_{status: "done", explanation: Expl, new_content: Final})).

/*  Prefer a model somebody chose over the one that sorts first. Discovery put
    `allam-2-7b` at the head of the list — a real model whose 4096-token limit
    the assistant's own request exceeds, so the default silently stopped
    working. The `curated` flag marks the models lps_llm's table names. */
default_model(Keys, Model) :-
	assistant_models(Keys, Ms), Ms \== [],
	(   member(M, Ms), get_dict(curated, M, true)
	->  true
	;   Ms = [M|_]
	), !,
	get_dict(name, M, Model).
default_model(_, _) :-
	throw(error(no_model, context(lps_assistant,
		'no LLM key is configured: set one in Misc ▸ API keys, or in the server environment'))).

		 /*******************************
		 *	   the two prompts	*
		 *******************************/

/* The canned prompts of §I.10.6. The user sees a button; the request that
   arrives is a sentinel, and the wording is ours. Keeping it here rather than
   in the browser means it can be improved without rebuilding the UI, and that
   the model cannot be steered by editing a page.
*/
resolve_command("__animate_2d__", Command, animate2d) :- !,
	Command = "Give this program a 2D animation.\n\n\c
Do it in ONE step: reply with a single {\"action\":\"layout\", \"plan\": …} and \c
nothing else. **Do not write any coordinates.** You are describing what is in the \c
picture; the geometry is computed for you, exactly, from the plan.\n\n\c
The plan:\n\c
{\"title\": \"a short caption\",\n\c
 \"orientation\": \"row\" or \"column\",\n\c
 \"groups\": [{\"id\":\"south\",\"label\":\"south bank\"}, …],   the containers\n\c
 \"gauges\": [{\"template\": \"heating(State)\",     a fluent whose argument is a VALUE\n\c
             \"value_var\": \"State\", \"label\": \"heating\"}],\n\c
 \"layers\": [{\"template\": \"loc(Object, Where)\",   a fluent of this program\n\c
              \"group_var\": \"Where\",                which argument names the container\n\c
              \"member_var\": \"Object\",              which argument names the thing\n\c
              \"shape\": \"raster\",                   raster | box | circle\n\c
              \"members\": [{\"id\":\"wolf\",\"icon\":\"wolf\"}, …]}]}\n\n\c
Choosing well is the part that needs you. Two shapes, and most programs are one \c
or the other:\n\c
- **Containers and members**, when a fluent says *where a thing is*: \c
`loc(Object, Where)`, `at(Robot, Room)`, `on(Block, Support)`. The **groups** are \c
the values the place argument takes — read the initial state and the causal laws to \c
find them — and the **members** are the things that move between them. Pick an \c
**icon** per member from the library offered above, by meaning; use shape \"box\" \c
or \"circle\" where no icon fits.\n\c
- **Gauges**, when a fluent says *what value something has*: `heating(on)`, \c
`temperature(14)`, `balance(alice, 100)`. Nothing moves; each gets a labelled \c
box showing what it currently says. A program of only gauges is a perfectly good \c
plan — give \"groups\": [] and \"layers\": [].\n\c
- Leave out anything that is neither. A plan with fewer, right things in it beats \c
one that forces a counter into a container.\n\n\c
The layout finishes the job: you do not need to `finish` afterwards.".
resolve_command("__animate_3d__", Command, animate3d) :- !,
	Command = "Write display3d/2 clauses for my program so that running it produces a \c
sensible 3D animation. Look at what the program is about — its fluents, its events, its \c
initial state — and lay the scene out in three dimensions, including a ground plane, a \c
camera and a light in the display3d(timeless, …) backdrop. Do not change any other part \c
of the program. Space things out: two boxes at the same position are one box, and the \c
usual mistake is putting everything at the origin. When you are done, use `scene` with \c
\"kind\":\"3d\" to check what was drawn: every fluent listed as *not drawn* is one your \c
clauses do not match, so fix them and check again. Do not finish while anything the \c
program is about is still invisible.".
resolve_command(C, C, none).

		 /*******************************
		 *	   the prompt		*
		 *******************************/

/* The Light assistant has no file tools, so everything it needs is inlined:
   the language reference, a couple of worked examples, the tool protocol and
   the program itself. docs/lps_summary.md is written to be inlined — that is
   why §I.10.7 schedules it *before* this milestone.
*/
system_prompt(Content, Extra, Req, Prompt) :-
	lps_doc('lps_summary.md', Syntax),
	extra_material(Extra, Req, Material),
	format(string(Prompt),
	       "You are the LPS Assistant. You help someone write and debug a program in LPS,~n\c
a logic-and-imperative language for describing agents, contracts and simulations.~n~n\c
Reply with EXACTLY ONE JSON object per turn and nothing else. The actions are:~n\c
  {\"action\":\"analyse\"}                       compile the current program, get diagnostics~n\c
  {\"action\":\"run\", \"cycles\":N}               run it (N optional), get the trace~n\c
  {\"action\":\"scene\", \"cycle\":N, \"kind\":\"2d\"}   what the display clauses drew at cycle N~n\c
  {\"action\":\"layout\", \"plan\":{…}}          replace the 2D scene from a plan (no coordinates)~n\c
  {\"action\":\"explain\", \"question\":\"why(happened(a), 2)\"}   ask about the last run~n\c
  {\"action\":\"edit\", \"new_content\":\"…the whole program…\"}   replace the program~n\c
  {\"action\":\"finish\", \"explanation\":\"markdown\", \"new_content\":\"…\"}  done~n~n\c
Rules:~n\c
- `new_content` is always the WHOLE program, never a fragment or a diff.~n\c
- After an `edit`, `analyse` before you `finish`. Never finish on a program you~n\c
  have not compiled. If the diagnostics are not empty, fix them and try again.~n\c
- Keep the user's own comments and formatting; change as little as you can.~n\c
- If you cannot do what was asked, `finish` and say so plainly.~n~n\c
=== THE LANGUAGE ===~n~w~n~n\c
~w~n\c
=== THE PROGRAM (this is what `analyse` and `run` see) ===~n~w~n",
	       [Syntax, Material, Content]).

extra_material(animate2d, Req, Material) :- !,
	icon_catalogue(Req, Icons),
	example_text('CLOUT_workshop/badlight', Badlight),
	format(string(Material),
	       "=== WRITING display/2 ===~n\c
The coordinate origin is BOTTOM LEFT and y grows upward. A scene is usually a few hundred~n\c
pixels across. `display(timeless, [[…],[…]])` is the backdrop — a list of property lists.~n\c
A display/2 clause must be callable with an unbound first argument, so put conditions in~n\c
the body and use no cuts and no if-then-else in the head.~n~n\c
Types: rectangle (from+to, or point+size), circle (point+radius), ellipse (point+size),~n\c
arc, line (from+to), path (segments), star (center, points, radius1, radius2),~n\c
regularPolygon, text (point+content), raster (position + icon or source), arrow (from+to,~n\c
biDirectional). Props: label, fillColor, strokeColor, strokeWidth, opacity, fontSize,~n\c
scale, shadowColor, shadowOffset, sendToBack, bringToFront.~n~n\c
Prefer `icon:NAME` over a `source:` URL — these are served locally and always load:~n~w~n~n\c
A worked example (legacy_lps1/examples/CLOUT_workshop/badlight.pl):~n~w~n",
	       [Icons, Badlight]).
extra_material(animate3d, _Req, Material) :- !,
	format(string(Material),
	       "=== WRITING display3d/2 ===~n\c
Right-handed coordinates with **y up**, in metres-ish units; a scene is usually tens of~n\c
units across. Types: box (size:[W,H,D]), sphere (radius), cylinder (radius, height),~n\c
cone, plane, ground, line (from+to), arrow (from+to), text (label), and two that belong~n\c
in the backdrop: camera (position, lookAt) and light (position, intensity).~n\c
Props: position:[X,Y,Z], rotation:[Rx,Ry,Rz] in degrees, size, color, opacity, label.~n~n\c
Always write a `display3d(timeless, [...])` with a ground plane, a camera and a light, or~n\c
the scene is unlit and the camera is nowhere useful. Example shape:~n~n\c
display3d(timeless, [~n\c
    [type:ground, size:[40,40], color:'#2a2f3a'],~n\c
    [type:camera, position:[14,12,16], lookAt:[0,0,0]],~n\c
    [type:light, position:[10,16,8], intensity:1.1] ]).~n~n\c
display3d(balance(P, V), [type:box, position:[X,H,0], size:[2,H2,2], color:green, label:P])~n\c
    :- position_of(P, X), H2 is V/10, H is H2/2.~n", []).
extra_material(_, _, "").

/* The catalogue the model picks from. Read from the manifest on this server
   rather than from the request: the browser sends its own copy, but a curl
   caller does not, and the assistant should not be less capable for being
   driven from a script. */
icon_catalogue(Req, Icons) :-
	(   icon_manifest_text(I)
	->  Icons = I
	;   get_dict(icons, Req, I2), string(I2), I2 \== ""
	->  Icons = I2
	;   Icons = "(icon library unavailable — use source: URLs)"
	).

icon_manifest_text(Text) :-
	lps_root_dir(Root),
	atomic_list_concat([Root, '/ui/icons/manifest.json'], Path),
	exists_file(Path),
	setup_call_cleanup(open(Path, read, In, [encoding(utf8)]),
			   json_read_dict(In, D),
			   close(In)),
	get_dict(icons, D, Icons),
	findall(S, ( member(I, Icons),
		     get_dict(name, I, N), get_dict(desc, I, De),
		     ( get_dict(concepts, I, Cs) -> true ; Cs = [] ),
		     atomic_list_concat(Cs, ', ', CS),
		     format(atom(S), "  ~w — ~w (~w)", [N, De, CS]) ),
		Lines),
	Lines \== [],
	atomic_list_concat(Lines, '\n', Text).

lps_doc(Name, Text) :-
	(   lps_root_dir(Root),
	    atomic_list_concat([Root, '/docs/', Name], Path),
	    exists_file(Path)
	->  read_file_to_string(Path, Text, [encoding(utf8)])
	;   Text = "(the language reference is not available on this server)"
	).

example_text(Name, Text) :-
	(   current_predicate(lps_http:example_source/2),
	    lps_http:example_source(Name, T)
	->  Text = T
	;   Text = ""
	).

lps_root_dir(Root) :-
	module_property(lps_assistant, file(F)),
	file_directory_name(F, Dir), file_directory_name(Dir, Src),
	file_directory_name(Src, Root).

		 /*******************************
		 *	    the loop		*
		 *******************************/

agent_loop(Id, _, _, _, Program, Step, Expl, Program) :-
	max_steps(Max), Step >= Max, !,
	format(string(Expl),
	       "I used all ~w of my steps without finishing, so the program is as I \c
last left it. Ask again — I will start from where this left the buffer — or ask \c
for a smaller piece of the job.", [Max]),
	progress(Id, "step limit reached").
agent_loop(Id, _, _, _, Program, _, Expl, Program) :-
	interrupted(Id), !,
	Expl = "Interrupted.".
agent_loop(Id, Model, Keys, Messages, Program, Step, Expl, Final) :-
	model_provider(Model, Provider),
	(   have_key(Provider, Keys, Key)
	->  true
	;   throw(error(no_key(Provider),
			context(lps_assistant, 'no API key for that provider')))
	),
	llm_request(Model, Messages, Reply, [api_key(Key), max_tokens(8000), timeout(180)]),
	(   parse_action(Reply, Action)
	->  handle(Id, Action, Program, Program1, Result, Done, Expl0),
	    (	Done == true
	    ->	Expl = Expl0, Final = Program1
	    ;	format(string(Obs), "~w", [Result]),
		append(Messages, [role(assistant, Reply), role(user, Obs)], Messages1),
		Step1 is Step + 1,
		agent_loop(Id, Model, Keys, Messages1, Program1, Step1, Expl, Final)
	    )
	;   append(Messages, [role(assistant, Reply),
			      role(user, "Reply with exactly one JSON action object.")], Messages1),
	    Step1 is Step + 1,
	    progress(Id, "no action in that reply; nudging"),
	    agent_loop(Id, Model, Keys, Messages1, Program, Step1, Expl, Final)
	).

model_provider(Model, Provider) :-
	( llm_model(Model, Provider, _) -> true ; Provider = openai ).

%	Models fence their JSON, or wrap it in prose, or both. LE2 has the same
%	problem and solves it the same way: find the outermost {...} and try.
parse_action(Reply, Action) :-
	extract_json(Reply, Dict),
	get_dict(action, Dict, A),
	Action = Dict.put(action, A).

extract_json(Text, Dict) :-
	string_codes(Text, Codes),
	json_span(Codes, Span),
	catch(( string_codes(S, Span),
		open_string(S, In),
		json_read_dict(In, Dict, [end_of_file(@(end))]) ), _, fail),
	is_dict(Dict), !.

json_span(Codes, Span) :-
	nth0(Start, Codes, 0'{),
	length(Prefix, Start), append(Prefix, Rest, Codes),
	balanced(Rest, 0, Span0), Span = Span0, !.

balanced([], _, []).
balanced([C|Cs], D, [C|Out]) :-
	(   C =:= 0'{ -> D1 is D + 1, balanced(Cs, D1, Out)
	;   C =:= 0'} -> D1 is D - 1, ( D1 =:= 0 -> Out = [] ; balanced(Cs, D1, Out) )
	;   balanced(Cs, D, Out)
	).

		 /*******************************
		 *	    the tools		*
		 *******************************/

handle(Id, Action, Program, Program, Result, false, "") :-
	get_dict(action, Action, "analyse"), !,
	progress(Id, "analyse"),
	tool_analyse(Program, Result).
handle(Id, Action, Program, Program, Result, false, "") :-
	get_dict(action, Action, "run"), !,
	progress(Id, "run"),
	( get_dict(cycles, Action, N), integer(N) -> Cycles = N ; Cycles = 0 ),
	tool_run(Program, Cycles, Result).
/*  The second stage of scene generation (§I.10.4e, lps_scene.pl). The model
 *  hands over a *plan* — containers, things, which template puts a thing in a
 *  container — and this replaces the program's display clauses with ones whose
 *  geometry was computed rather than imagined. The model never writes a
 *  coordinate, which is the whole point: it was the only part of the job it was
 *  reliably bad at. */
handle(Id, Action, Program, New, "", true, Expl) :-
	get_dict(action, Action, "layout"), !,
	progress(Id, "layout"),
	(   get_dict(plan, Action, Plan), is_dict(Plan)
	->  scene_clauses(Plan, Clauses, Diags),
	    (   Clauses == ""
	    ->  New = Program,
		findall(L, ( member(D, Diags), diag_line(D, L) ), Ls),
		atomic_list_concat(Ls, '\n', LT),
		format(string(Expl), "I could not lay that plan out.~n~w", [LT])
	    ;   strip_display(Program, Stripped),
		string_concat(Stripped, "\n\n", P1),
		string_concat(P1, Clauses, New),
		tool_analyse(New, A),
		plan_summary(Plan, Diags, A, Expl)
	    )
	;   New = Program,
	    Expl = "I need a `plan` object to lay out; nothing was changed."
	).
handle(Id, Action, Program, Program, Result, false, "") :-
	get_dict(action, Action, "scene"), !,
	progress(Id, "scene"),
	( get_dict(cycle, Action, C), integer(C) -> Cycle = C ; Cycle = -1 ),
	( get_dict(kind, Action, "3d") -> Decl = display3d ; Decl = display ),
	tool_scene(Program, Cycle, Decl, Result).
handle(Id, Action, Program, Program, Result, false, "") :-
	get_dict(action, Action, "explain"), !,
	progress(Id, "explain"),
	( get_dict(question, Action, Q) -> true ; Q = "why_not(happened(x), 1)" ),
	tool_explain(Program, Q, Result).
handle(Id, Action, _Program, New, Result, false, "") :-
	get_dict(action, Action, "edit"), !,
	get_dict(new_content, Action, New),
	progress(Id, "edit"),
	tool_analyse(New, Result).
handle(_Id, Action, Program, Final, "", true, Expl) :-
	get_dict(action, Action, "finish"), !,
	( get_dict(explanation, Action, Expl) -> true ; Expl = "Done." ),
	( get_dict(new_content, Action, N), string(N), N \== "" -> Final = N ; Final = Program ).
handle(_, _, P, P, "Unknown action. Use analyse, run, explain, edit or finish.", false, "").

/* The tools are the panes' own operations, called in process. A model that
   asks "does this compile?" gets the same answer the editor's problem strip
   shows, because it is the same call. */
tool_analyse(Program, Result) :-
	with_compiled(Program, Diags, _),
	(   Diags == []
	->  Result = "analyse: no problems."
	;   findall(S, ( member(D, Diags), diag_line(D, S) ), Lines),
	    atomic_list_concat(Lines, '\n', Body),
	    format(string(Result), "analyse:~n~w", [Body])
	).

diag_line(diag(Sev, Code, Pos, Msg, _), S) :-
	( Pos = src(_, Line, _, _) -> true ; Line = 0 ),
	format(string(S), "  ~w line ~w: ~w [~w]", [Sev, Line, Msg, Code]).

tool_run(Program, Cycles, Result) :-
	with_compiled(Program, Diags, P),
	(   P == none
	->  tool_analyse(Program, Result)
	;   lps_session_new(P, [dc], S0),
	    ( Cycles > 0 -> Stop = cycles(Cycles) ; Stop = end ),
	    catch(lps_session_run(S0, Stop, S, Trace), E,
		  ( message_to_text(E, M), throw(run_failed(M)) )),
	    lps_session_status(S, Status),
	    trace_summary(Trace, Summary),
	    length(Diags, ND),
	    format(string(Result), "run: ~w~n~w~n(~w diagnostic(s))", [Status, Summary, ND])
	).

/* What the display clauses actually drew.
 *
 * "Run it and check the scene is not empty" was an instruction the model could
 * only guess at: `run` reports events, and a program whose trace is perfect can
 * still draw nothing. What settles it is per subject — a fluent no display
 * clause matches is simply invisible, and naming that fluent is the difference
 * between the model fixing its clause and the model declaring victory over a
 * background rectangle. Which is what it did, before this existed.
 */
tool_scene(Program, Cycle0, Decl, Result) :-
	with_compiled(Program, _, P),
	(   P == none
	->  tool_analyse(Program, Result)
	;   lps_session_new(P, [dc], S0),
	    catch(lps_session_run(S0, end, S, _), E,
		  ( message_to_text(E, M), throw(run_failed(M)) )),
	    lps_session_time(S, Max),
	    ( Cycle0 >= 0 -> Cycle is min(Cycle0, Max) ; Cycle is min(1, Max) ),
	    lps_session_scene(S, Cycle, Decl, scene(_, Timeless, Items)),
	    lps_session_trace(S, Trace),
	    scene_subjects(Trace, Cycle, Subjects),
	    findall(Sub, member(visual(_, Sub, _), Items), Drawn),
	    findall(Line, ( member(visual(_, Sub, Props), Items),
			    scene_line(Sub, Props, Line) ), Lines),
	    exclude(drawn_in(Drawn), Subjects, Missing),
	    maplist(term_to_line, Missing, MissingLines),
	    length(Timeless, NT), length(Items, NI),
	    ( Lines == [] -> Body = "  (nothing drawn)"
	    ; atomic_list_concat(Lines, '\n', Body) ),
	    ( MissingLines == [] -> Miss = "  (none)"
	    ; atomic_list_concat(MissingLines, ', ', Miss0),
	      format(string(Miss), "  ~w", [Miss0]) ),
	    format(string(Result),
		   "scene (~w) at cycle ~w of ~w: ~w object(s), ~w backdrop item(s)~n\c
~w~nnot drawn — no ~w clause matched:~n~w",
		   [Decl, Cycle, Max, NI, NT, Body, Decl, Miss])
	).

drawn_in(Drawn, S) :- memberchk(S, Drawn).

%	Everything that *could* have been drawn at this cycle.
scene_subjects(Trace, Cycle, Subjects) :-
	( memberchk(stage(fluents, Cycle, Fs), Trace) -> true ; Fs = [] ),
	( memberchk(stage(events, Cycle, Es), Trace) -> true ; Es = [] ),
	append(Fs, Es, Subjects).

scene_line(Sub, Props, Line) :-
	( memberchk(type:Type, Props) -> true ; Type = '(no type)' ),
	format(string(Line), "  ~q → ~w", [Sub, Type]).

term_to_line(T, S) :- format(string(S), "~q", [T]).

/*  Remove every display/2 or display3d/2 clause, so the generated ones replace
    rather than join them. Line based, because the program is text at this
    point and a clause we cannot parse is one we must not silently delete. */
strip_display(Program, Out) :-
	split_string(Program, "\n", "", Lines),
	strip_lines(Lines, none, Kept),
	atomic_list_concat(Kept, '\n', Out0),
	atom_string(Out0, Out).

strip_lines([], _, []).
strip_lines([L|Ls], State, Out) :-
	(   State == in_clause
	->  ( clause_ends(L) -> S1 = none ; S1 = in_clause ),
	    strip_lines(Ls, S1, Out)
	;   display_head(L)
	->  ( clause_ends(L) -> S1 = none ; S1 = in_clause ),
	    strip_lines(Ls, S1, Out)
	;   Out = [L|Out1], strip_lines(Ls, none, Out1)
	).

display_head(L) :-
	( sub_string(L, 0, _, _, "display(") ; sub_string(L, 0, _, _, "display3d(") ), !.

%	Does this line end a clause? The two goals were the right ones in the
%	wrong order: `string_concat(_, ".", Trimmed)` before Trimmed is bound is
%	an instantiation error, not a test.
clause_ends(L) :-
	split_string(L, "%", "", [Code|_]),
	normalize_space(string(Trimmed), Code),
	string_concat(_, ".", Trimmed), !.

/*  What the layout did, in the user's terms. The model does not get to
    narrate this: it did not choose the geometry, and saying it did would be
    the assistant taking credit for the one part it was kept away from. */
plan_summary(Plan, Diags, Analysis, Expl) :-
	( get_dict(groups, Plan, Gs), is_list(Gs) -> length(Gs, NG) ; NG = 0 ),
	(   get_dict(layers, Plan, Ls), is_list(Ls)
	->  findall(N, ( member(L, Ls), get_dict(members, L, Ms), is_list(Ms), length(Ms, N) ), Ns),
	    sum_list(Ns, NM0)
	;   NM0 = 0
	),
	( get_dict(gauges, Plan, Gg), is_list(Gg) -> length(Gg, NGa) ; NGa = 0 ),
	NM is NM0 + NGa,
	(   Diags == []
	->  Notes = ""
	;   findall(Line, ( member(D, Diags), diag_line(D, Line) ), DLs),
	    atomic_list_concat(DLs, '\n', DT),
	    format(string(Notes), "~nNotes on the plan:~n~w", [DT])
	),
	format(string(Expl),
	       "I planned the scene — ~w container(s), ~w thing(s) — and the geometry was \c
computed from it rather than written by me: every position comes from the generated \c
`lps_slot/4` table, so nothing overlaps and a thing keeps its column wherever it is. \c
Edit a slot and everything that ever sits in it moves.~n~n~w~w",
	       [NG, NM, Analysis, Notes]).

trace_summary(Trace, Summary) :-
	findall(Line,
		( member(stage(events, C, Items), Trace), Items \== [],
		  format(atom(Line), "  cycle ~w: ~q", [C, Items]) ),
		Lines0),
	( Lines0 == [] -> Lines = ["  (no events)"] ; length(Lines0, N), N > 12 ->
	    length(Head, 12), append(Head, _, Lines0), append(Head, ["  …"], Lines) ; Lines = Lines0 ),
	atomic_list_concat(Lines, '\n', Summary).

tool_explain(Program, QuestionS, Result) :-
	with_compiled(Program, _, P),
	(   P == none
	->  Result = "explain: the program does not compile."
	;   lps_session_new(P, [dc], S0),
	    lps_session_run(S0, end, S, _),
	    catch(( term_string(Q, QuestionS),
		    lps_session_explain(S, Q, explanation(_, Verdict, Tree)),
		    explanation_text(explanation(Q, Verdict, Tree), Lines),
		    atomic_list_concat(Lines, '\n', Body),
		    format(string(Result), "explain (~w):~n~w", [Verdict, Body]) ),
		  _, Result = "explain: I could not parse that question.")
	).

with_compiled(Program, Diags, P) :-
	(   current_predicate(lps_http:source_terms/3)
	->  lps_http:source_terms(Program, Terms, ReadDiags)
	;   ReadDiags = [], Terms = []
	),
	(   ReadDiags \== []
	->  Diags = ReadDiags, P = none
	;   lps_compile(terms(Terms), legacy, [dc], P0, CDiags),
	    Diags = CDiags,
	    ( diags_ok(CDiags) -> P = P0 ; P = none )
	).

		 /*******************************
		 *   English → events (M18)	*
		 *******************************/

/* The live panel's natural-language box (§II.0). The model is given the
   program's *declared* events and asked to pick one and fill it in; the answer
   is shown to the user before anything is injected, because an agent acting on
   a mistranslated observation is the failure mode this design exists to
   prevent.
*/
assistant_translate(P, Text, Opts, Events) :-
	( memberchk(keys(Keys), Opts) -> true ; Keys = _{} ),
	( memberchk(model(M), Opts), M \== null -> Model = M ; default_model(Keys, Model) ),
	%  If the caller says which predicates this channel may carry, offer the
	%  model those and nothing else. Anything wider is a prompt asking to be
	%  ignored: the allow-list is enforced at injection anyway, so a
	%  translation outside it can only ever be a refused event.
	(   memberchk(allowed(Allowed), Opts), is_list(Allowed), Allowed \== []
	->  allowed_text(Allowed, Decls)
	;   declared_events(P, Decls)
	),
	format(string(System),
	       "Translate an English sentence into ONE LPS event term, chosen from this~n\c
program's declared events:~n~w~n~n\c
Reply with exactly one JSON object: {\"events\":[\"term(arg,…)\"]}. Use only the~n\c
predicates listed. If nothing fits, reply {\"events\":[]}.", [Decls]),
	model_provider(Model, Provider),
	have_key(Provider, Keys, Key),
	llm_request(Model, [role(system, System), role(user, Text)], Reply,
		    [api_key(Key), max_tokens(400), timeout(60)]),
	(   extract_json(Reply, D), get_dict(events, D, Es), is_list(Es)
	->  Events = Es
	;   Events = []
	).

/* Only things the program can actually *receive*. p_event/2 is generous — a
   bare literal in a rule body with no declaration and no timeless clause is
   inferred to be an event — so a predicate that has timeless clauses is
   filtered out here. Without it the model was offered `destructive/1`, which
   is a belief about the world rather than a thing that happens in it, and
   duly picked it.
*/
allowed_text(Allowed, Text) :-
	findall(S, ( member(A, Allowed), format(atom(S), "  ~w", [A]) ), Ss),
	atomic_list_concat(Ss, '\n', Text).

declared_events(P, Text) :-
	findall(S, ( ( p_event(P, E) ; p_action(P, E) ),
		     \+ functor(E, lps_terminate, _),
		     \+ p_l_timeless(P, E, _),
		     format(atom(S), "  ~q", [E]) ), Ss0),
	sort(Ss0, Ss),
	( Ss == [] -> Text = "  (none declared)" ; atomic_list_concat(Ss, '\n', Text) ).

/*  A provider's 400 carries a sentence a person can act on — "`max_tokens`
    must be less than or equal to `4096`" — wrapped in three layers of Prolog
    term. Dig it out; the whole term is no use to the reader. */
message_to_text(error(llm_api_error(_, Payload), _), S) :- !,
	(   api_error_message(Payload, M)
	->  format(string(S), "the model provider refused the request: ~w", [M])
	;   format(string(S), "the model provider refused the request (~q)", [Payload])
	).
message_to_text(E, S) :-
	(   catch(message_to_codes_(E, S0), _, fail)
	->  S = S0
	;   format(string(S), "~q", [E])
	).

api_error_message(P, M) :- is_dict(P), get_dict(error, P, E), !, api_error_message(E, M).
api_error_message(P, M) :- is_dict(P), get_dict(message, P, M), !.
api_error_message(P, M) :- string(P), !, M = P.

message_to_codes_(E, S) :- format(string(S), "~q", [E]).
