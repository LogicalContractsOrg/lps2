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
	assistant_translate/4,     % +Program, +Text, +Opts, -Events
	%  Model and key selection, for the other features that need a model:
	%  the live panel's translator and Logical English's English→LE.
	assistant_default_model/2, % +Keys, -Model
	assistant_key_for/3        % +Model, +Keys, -Key
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
:- use_module(lps_ids).

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
	with_mutex(lps_jobs,
		   ( retract(job_counter(N)), N1 is N + 1,
		     assertz(job_counter(N1)) )),
	format(atom(Base), 'job~w', [N1]),
	%  Tagged with this process's own id (lps_ids.pl): a job lives in the
	%  memory of the process that started it, and a poll that reaches a
	%  different one must be told so rather than shown a namesake.
	tagged_id(Base, Id),
	set_job(Id, _{status: running, output: [], explanation: "",
		      new_content: null, error: null, interrupt: false}),
	thread_create(run_job(Id, Req), _, [detached(true)]).

assistant_status(Id, Status) :-
	Empty = _{status: "unknown", output: [], explanation: "",
		  new_content: null, error: null, interrupt: false},
	(   job_state(Id, S)
	->  Status = Empty.put(S)
	;   Status = Empty.put(error, "no such job")
	).

assistant_interrupt(Id) :- with_mutex(lps_jobs, interrupt_(Id)).

interrupt_(Id) :-
	( job(Id, S) -> set_job_(Id, S.put(interrupt, true)) ; true ).

/*  One record per job, written by the job's own thread and read by whichever
    HTTP worker is polling it — so, as in `lps_live.pl`, every touch is under a
    mutex. Two reasons, and the second is the one that bites. A bare
    `retractall`-then-`assertz` has a window in which the job does not exist,
    and a poll landing in it is told "no such job" about a job that is running
    happily; the editor believes that and stops polling. And `progress/2` is a
    read-modify-write, so an interrupt arriving between its read and its write
    was simply dropped.

    The window is only negligible while the CPU is not oversubscribed — measured
    at 0 misses in 80,000 polls with four reader threads on eight cores, and 35%
    of 2.4 million with twelve on the same eight, because a writer descheduled
    inside the window holds it open for a scheduler quantum. `fly.toml` says
    `cpus = 1`. The same note, at more length, is in `lps_http.pl`.
*/
job_state(Id, S) :- with_mutex(lps_jobs, job(Id, S)).

set_job(Id, S) :- with_mutex(lps_jobs, set_job_(Id, S)).

set_job_(Id, S) :- retractall(job(Id, _)), assertz(job(Id, S)).

%	Merge into whatever the record says *now*, rather than into a copy the
%	caller read some time ago — the caller's copy predates its own tool
%	call, which is where the progress lines it is trying to keep came from.
update_job(Id, New) :- with_mutex(lps_jobs, update_job_(Id, New)).

update_job_(Id, New) :-
	( job(Id, S) -> true ; S = _{} ),
	set_job_(Id, S.put(New)).

progress(Id, Line) :- with_mutex(lps_jobs, progress_(Id, Line)).

progress_(Id, Line) :-
	(   job(Id, S)
	->  append(S.output, [Line], Out),
	    set_job_(Id, S.put(output, Out))
	;   true
	).

interrupted(Id) :- job_state(Id, S), S.interrupt == true.

/*  A job leaves `running` exactly once, whatever happens.
 *
 *  `catch/3` covers a thrown error and nothing else, so a *failed* goal — a
 *  request missing `command`, a dict key that is not there — left the record
 *  saying `running` for ever. The browser polls that word: the panel showed
 *  "thinking…" until the tab was closed, and the only account of what had
 *  happened was a "Thread running run_job(…) died due to failure" in the
 *  server's log, which nobody polling an HTTP endpoint is reading. Observed at
 *  four minutes on a request that never had a chance.
 */
run_job(Id, Req) :-
	(   catch(run_job_(Id, Req), E,
		  ( message_to_text(E, M),
		    update_job(Id, _{status: "error", error: M}) ))
	->  true
	;   update_job(Id, _{status: "error",
			     error: "the assistant could not start on that request \c
— it was missing something it needs (see the server log)"})
	),
	%  Belt and braces: whatever path was taken, the record must not still say
	%  `running`, because that is the one answer the editor cannot recover from.
	(   job_state(Id, S), get_dict(status, S, "running")
	->  update_job(Id, _{status: "error", error: "the assistant stopped without \c
saying why"})
	;   true
	).

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
	update_job(Id, _{status: "done", explanation: Expl, new_content: Final}).

/*  Prefer a model somebody chose over the one that sorts first. Discovery put
    `allam-2-7b` at the head of the list — a real model whose 4096-token limit
    the assistant's own request exceeds, so the default silently stopped
    working. The `curated` flag marks the models lps_llm's table names. */
%!	assistant_default_model(+Keys, -Model) is det.
assistant_default_model(Keys, Model) :- default_model(Keys, Model).

%!	assistant_key_for(+Model, +Keys, -Key) is semidet.
%
%	The key that model needs, environment first. Exported because every
%	feature that reaches a model — not only the assistant — has to answer
%	the same question the same way.
assistant_key_for(Model, Keys, Key) :-
	model_provider(Model, Provider),
	have_key(Provider, Keys, Key).

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
	plan_prompt("2D", "2d", Command).
resolve_command("__animate_3d__", Command, animate3d) :- !,
	plan_prompt("3D", "3d", Command).
resolve_command(C, C, none).

/*  One prompt for both dimensions.
 *
 *  "Animate in 3D" used to ask the model for `display3d/2` clauses *with
 *  coordinates in them* — exactly the job §I.10.4e took away from it in two
 *  dimensions, handed back with one more axis to get wrong. It produced what
 *  you would expect: everything at the origin, or a camera inside a wall. Now
 *  both buttons ask for the same plan and `lps_scene.pl` renders it twice.
 */
plan_prompt(Label, Kind, Command) :-
	format(string(Command),
	       "Give this program a ~w animation.\n\n\c
Do it in ONE step: reply with a single {\"action\":\"layout\", \"kind\":\"~w\", \"plan\": …} \c
and nothing else. **Do not write any coordinates.** You are describing what is in the \c
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
              \"members\": [{\"id\":\"wolf\",\"icon\":\"wolf\"}, …]}],\n\c
 \"stacks\": [{\"template\": \"on(Block, Support)\",   a thing standing on another thing\n\c
              \"member_var\": \"Block\",               which argument names the thing\n\c
              \"support_var\": \"Support\",            which argument names what it stands on\n\c
              \"ground\": [\"table\"],                 what the piles stand on, if named\n\c
              \"members\": [{\"id\":\"a\"}, {\"id\":\"b\"}, …]}]}\n\n\c
Choosing well is the part that needs you, and the choice is between three shapes:\n\n\c
- **Containers and members**, when a fluent says *where a thing is* and the place is \c
NOT one of the things: `loc(Object, Where)`, `at(Robot, Room)`, `in(Parcel, Van)`. The \c
**groups** are the values the place argument takes — read the initial state and the \c
causal laws to find them — and the **members** are the things that move between them. \c
Pick an **icon** per member from the library offered above, by meaning; use shape \c
\"box\" or \"circle\" where no icon fits.\n\n\c
- **Stacks**, when a thing stands on *another thing of the same kind*: \c
`on(Block, Support)`, `above(Plate, Plate)`, `carries(Robot, Robot)`. The tell is that \c
the same names appear on both sides — `on(a, b)` and `on(b, c)` — so `b` is both a \c
thing and a place. This is a **tower**, not one box per thing: use \"stacks\", list \c
every thing once in \"members\", and name the floor (`table`, `ground`, `floor`) in \c
\"ground\". Do NOT model this as containers: a container per block draws seven empty \c
boxes each holding one small square, every block twice, and no tower anywhere. Height \c
and column are computed from the state at each cycle, so the blocks move in and out of \c
the pile as the program moves them.\n\n\c
- **Gauges**, when a fluent says *what value something has*: `heating(on)`, \c
`temperature(14)`, `balance(alice, 100)`. Nothing moves; each gets a labelled box \c
showing what it currently says. A program of only gauges is a perfectly good plan — \c
give \"groups\": [] and \"layers\": [].\n\n\c
Leave out anything that is none of the three. A plan with fewer, right things in it \c
beats one that forces a counter into a container. A program can need more than one \c
shape at once; it can need only one.\n\n\c
The layout finishes the job: you do not need to `finish` afterwards.",
	       [Label, Kind]).

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
  {\"action\":\"layout\", \"kind\":\"2d\"|\"3d\", \"plan\":{…}}  replace that scene from a plan (no coordinates)~n\c
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

/*  What the model needs in order to *plan*, which is a different list from what
    it needed in order to *write* display clauses. The shape vocabulary and the
    coordinate conventions are gone: it does not write either. What is left is
    the reading — which fluent is which shape — and the icon catalogue, which is
    the one place a plan still names something concrete. */
extra_material(animate2d, Req, Material) :- !,
	icon_catalogue(Req, Icons),
	format(string(Material),
	       "=== READING THE PROGRAM FOR A PLAN ===~n\c
Work from the declarations, the initial state and the causal laws, in that order.~n\c
- `fluents f(A, B).` says which terms are states worth drawing.~n\c
- `initially …` names most of the things and most of the places in one line.~n\c
- an `updates Old to New in f(…)` law says which argument *moves*, which is~n\c
  usually the argument that decides where a thing is drawn.~n\c
- if the same names appear on BOTH sides of a fluent — `on(a,b)`, `on(b,c)` —~n\c
  it is a stack, not a set of containers. Check this before anything else; it~n\c
  is the reading that goes wrong most often.~n\c
- a fluent whose moving argument is a number or an on/off word is a gauge.~n~n\c
Every member takes an `icon`, and these are served by this server and always~n\c
load — prefer one to a colour wherever a thing has an obvious picture:~n~w~n",
	       [Icons]).
/*  Both animate buttons get the same material now, because both go through the
    plan. What the model still has to choose is which *shape* each fluent is and
    what each thing looks like, and the icon catalogue is what makes the second
    of those possible without inventing a URL. */
extra_material(animate3d, Req, Material) :- !,
	extra_material(animate2d, Req, M0),
	string_concat(M0,
	    "\n=== IN THREE DIMENSIONS ===\nThe same plan is laid out standing up: the \c
container grid becomes a floor plan, things stand on their slab, and a stack is a \c
tower. The ground plane, the camera and the light are computed and written for you — \c
do not write a `display3d(timeless, …)` yourself, and do not write coordinates. \c
Icons are a 2D idea and are ignored here; `color` on a member is not.\n",
	    Material).
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
	%  The same plan grammar in both dimensions (§I.10.4e). `kind` says which
	%  declaration to write; only that one is replaced, so a program can carry
	%  a 2D scene and a 3D one at the same time and "Animate in 3D" does not
	%  quietly delete the picture the user already had.
	( get_dict(kind, Action, "3d") -> Kind = threed, Decl = display3d
	; Kind = twod, Decl = display ),
	(   get_dict(plan, Action, Plan), is_dict(Plan)
	->  scene_clauses(Plan, Kind, Clauses, Diags),
	    (   Clauses == ""
	    ->  New = Program,
		findall(L, ( member(D, Diags), diag_line(D, L) ), Ls),
		atomic_list_concat(Ls, '\n', LT),
		format(string(Expl), "I could not lay that plan out.~n~w", [LT])
	    ;   strip_display(Program, Decl, Stripped),
		string_concat(Stripped, "\n\n", P1),
		string_concat(P1, Clauses, New),
		tool_analyse(New, A),
		plan_summary(Plan, Decl, Diags, A, Expl)
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

/*  Remove the clauses of *one* declaration, so the generated ones replace
    rather than join them. Line based, because the program is text at this
    point and a clause we cannot parse is one we must not silently delete.

    Also removes the helper tables the last layout wrote — a stale
    `lps_slot/4` beside a freshly generated `lps_column/2` is two answers to
    the same question, and the first one found wins. */
strip_display(Program, Decl, Out) :-
	split_string(Program, "\n", "", Lines),
	strip_lines(Lines, Decl, none, Kept),
	atomic_list_concat(Kept, '\n', Out0),
	atom_string(Out0, Out).

strip_lines([], _, _, []).
strip_lines([L|Ls], Decl, State, Out) :-
	(   State == in_clause
	->  ( clause_ends(L) -> S1 = none ; S1 = in_clause ),
	    strip_lines(Ls, Decl, S1, Out)
	;   generated_head(L, Decl)
	->  ( clause_ends(L) -> S1 = none ; S1 = in_clause ),
	    strip_lines(Ls, Decl, S1, Out)
	;   Out = [L|Out1], strip_lines(Ls, Decl, none, Out1)
	).

generated_head(L, Decl) :-
	(   atom_concat(Decl, '(', Head), sub_string(L, 0, _, _, Head)
	;   helper_prefix(Decl, P), sub_string(L, 0, _, _, P)
	), !.

/*  The tables belong to one declaration each, which is why the 3D ones carry a
    `3`: a program may hold a 2D scene and a 3D scene at once, and one
    `lps_column/2` in two different unit systems would put the 3D tower in
    pixels. `lps_look/3` is the exception and is deliberately shared — what a
    thing looks like is the same fact in both pictures — so it is stripped and
    re-emitted whichever is being generated. */
helper_prefix(display,   "lps_slot(").
helper_prefix(display,   "lps_column(").
helper_prefix(display,   "lps_pile_x(").
helper_prefix(display,   "lps_pile_x_(").
helper_prefix(display,   "lps_pile_top(").
helper_prefix(display,   "lps_pile_top_(").
helper_prefix(display3d, "lps_slot3(").
helper_prefix(display3d, "lps_column3(").
helper_prefix(display3d, "lps_pile_x3(").
helper_prefix(display3d, "lps_pile_x3_(").
helper_prefix(display3d, "lps_pile_top3(").
helper_prefix(display3d, "lps_pile_top3_(").
helper_prefix(_,         "lps_look(").

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
plan_summary(Plan, Decl, Diags, Analysis, Expl) :-
	( get_dict(groups, Plan, Gs), is_list(Gs) -> length(Gs, NG) ; NG = 0 ),
	(   get_dict(layers, Plan, Ls), is_list(Ls)
	->  findall(N, ( member(L, Ls), get_dict(members, L, Ms), is_list(Ms), length(Ms, N) ), Ns),
	    sum_list(Ns, NM0)
	;   NM0 = 0
	),
	( get_dict(gauges, Plan, Gg), is_list(Gg) -> length(Gg, NGa) ; NGa = 0 ),
	(   get_dict(stacks, Plan, St), is_list(St)
	->  findall(N2, ( member(S, St), get_dict(members, S, Ms2), is_list(Ms2), length(Ms2, N2) ), Ns2),
	    sum_list(Ns2, NS)
	;   NS = 0
	),
	NM is NM0 + NGa + NS,
	%  A promoted stack is the interesting thing that happened, so it leads
	%  rather than sitting in the notes: the user asked for a picture of
	%  blocks world and got a tower without asking for one.
	(   member(diag(_, scene_promoted_stack, _, _, _), Diags)
	->  How = "the fluent turned out to be a support relation — the same names \c
appear on both sides of it — so it is drawn as piles rather than as one box per thing, \c
and each thing's height and column are worked out from the state at the cycle you are \c
looking at"
	;   NS > 0
	->  How = "the piles are drawn from the state at the cycle you are looking \c
at, so a thing moves in and out of a tower as the program moves it"
	;   How = "every position comes from the generated slot table, so nothing \c
overlaps and a thing keeps its column wherever it is; edit a slot and everything that \c
ever sits in it moves"
	),
	(   Diags == []
	->  Notes = ""
	;   findall(Line, ( member(D, Diags), diag_line(D, Line) ), DLs),
	    atomic_list_concat(DLs, '\n', DT),
	    format(string(Notes), "~nNotes on the plan:~n~w", [DT])
	),
	format(string(Expl),
	       "I planned the scene — ~w container(s), ~w thing(s) — and wrote it as \c
`~w` clauses. The geometry is computed from the plan rather than written by me: ~w.~n~n~w~w",
	       [NG, NM, Decl, How, Analysis, Notes]).

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
