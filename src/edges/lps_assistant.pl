/* lps_assistant.pl — the LPS Assistant (M16, §I.10.6).
 *
 * A bounded agentic loop that owns a conversation and a tool-calling cycle,
 * modelled on LE2's "light" assistant (docs/dev/assistant-light.md): Prolog
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
:- use_module(library(pairs)).
:- use_module(library(strings)).
:- use_module(library(http/json)).
:- use_module('../core/lps_diag').
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../core/lps_explain').
:- use_module(lps_llm).
:- use_module(lps_scene).
:- use_module(lps_le).
:- use_module(lps_ids).
:- use_module(lps_docs_search).

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
		      new_content: null, new_companion: null,
		      error: null, interrupt: false}),
	thread_create(run_job(Id, Req), _, [detached(true)]).

assistant_status(Id, Status) :-
	Empty = _{status: "unknown", output: [], explanation: "",
		  new_content: null, new_companion: null,
		  error: null, interrupt: false},
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
		  ( job_error_text(Req, E, M),
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

/*  A provider's refusal, in terms of the thing the user was doing.
 *
 *  "This model's maximum context length is 8192 tokens. However, your messages
 *  resulted in 12543 tokens. Please reduce the length of the messages." is a
 *  true sentence about somebody else's arithmetic, and there is nothing in it
 *  the person who pressed *Animate in 2D* can act on: they did not choose the
 *  length of the messages, this file did. So say whose it is and what to do.
 */
job_error_text(Req, E, Text) :-
	message_to_text(E, Raw),
	(   context_length_refusal(Raw)
	->  ( get_dict(model, Req, M), M \== null -> Model = M ; Model = 'that model' ),
	    bigger_models(8192, Alternatives),
	    format(string(Text),
		   "~w cannot be told this much at once.~n~n\c
The request carries the language reference, the icon catalogue and your \c
program. ~w~n~nThe provider said: ~w", [Model, Alternatives, Raw])
	;   Text = Raw
	).

context_length_refusal(S) :-
	string_lower(S, L),
	(   sub_string(L, _, _, _, "maximum context length")
	;   sub_string(L, _, _, _, "context_length_exceeded")
	;   sub_string(L, _, _, _, "reduce the length of the messages")
	;   sub_string(L, _, _, _, "too many tokens")
	), !.

run_job_(Id, Req) :-
	get_dict(command, Req, Command0),
	( get_dict(content, Req, Content) -> true ; Content = "" ),
	( get_dict(api_keys, Req, Keys) -> true ; Keys = _{} ),
	( get_dict(model, Req, M), M \== null -> Model = M ; default_model(Keys, Model) ),
	buffer_context(Req, Ctx, Companion),
	resolve_command(Ctx, b(Content, Companion), Command0, Command, Extra),
	system_prompt(Ctx, b(Content, Companion), Extra, Req, System0),
	%  The documentation searched for what the person typed, behind the
	%  scenes (lps_docs_search.pl): a question about LPS or the IDE is then
	%  answered with a few links to where the documentation says it. Not for
	%  the toolbar's own commands, which are not questions.
	(   Extra == none
	->  docs_material(Command, Docs),
	    string_concat(System0, Docs, System)
	;   System = System0
	),
	Messages = [role(system, System), role(user, Command)],
	progress(Id, "thinking…"),
	agent_loop(Id, Ctx, Model, Keys, Messages, b(Content, Companion), 0, Expl,
		   b(Final, FinalComp)),
	%  Only a companion that *changed* comes back: the editor opens a tab for
	%  whatever it is given, and handing back the text it sent would open one
	%  for a file the assistant never touched.
	( FinalComp \== Companion, FinalComp \== "" -> Comp = FinalComp ; Comp = null ),
	update_job(Id, _{status: "done", explanation: Expl,
			 new_content: Final, new_companion: Comp}).

/*  Which language the buffer is in, and what else belongs to it.
 *
 *  The assistant used to be told a program and nothing about it, so it read
 *  every buffer as LPS external syntax. Handed a Logical English document that
 *  is what it did: `analyse` reported `syntax error: operator_expected` at line
 *  1 of a perfectly good `.le` file, and the `layout` tool — whose job is to
 *  write `display/2` clauses — appended Prolog to the English, which LE2 then
 *  correctly refused as an unknown section. Both follow from one missing fact,
 *  so the fact is now carried: `name` says what the file is called, and the
 *  extension says what it is.
 *
 *  A `.le` document's Prolog goes in its `.lps` companion (§7 of
 *  docs/user/reference/le-for-lps.md), which the caller sends as text because the browser
 *  has no file system to find it in.
 */
buffer_context(Req, ctx(Syntax, Name, CName), Companion) :-
	(   get_dict(name, Req, N), string(N), N \== ""
	->  atom_string(Name, N)
	;   Name = 'buffer.lps'
	),
	( file_name_extension(_, le, Name) -> Syntax = le ; Syntax = lps ),
	lps_le_companion_name(Name, CName),
	(   get_dict(companion, Req, C), string(C)
	->  Companion = C
	;   Companion = ""
	).

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
resolve_command(Ctx, Buf, "__animate_2d__", Command, animate2d) :- !,
	plan_prompt(Ctx, Buf, "2D", "2d", Command).
resolve_command(Ctx, Buf, "__animate_3d__", Command, animate3d) :- !,
	plan_prompt(Ctx, Buf, "3D", "3d", Command).
resolve_command(_, _, C, C, none).

/*  One prompt for both dimensions.
 *
 *  "Animate in 3D" used to ask the model for `display3d/2` clauses *with
 *  coordinates in them* — exactly the job §I.10.4e took away from it in two
 *  dimensions, handed back with one more axis to get wrong. It produced what
 *  you would expect: everything at the origin, or a camera inside a wall. Now
 *  both buttons ask for the same plan and `lps_scene.pl` renders it twice.
 */
plan_prompt(Ctx, Buf, Label, Kind, Command) :-
	focus_material(Ctx, Buf, Focus),
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
              \"members\": [{\"id\":\"wolf\",\"icon\":\"wolf\",\n\c
                            \"pattern\":\"noise\",       a fill for its surface (optional)\n\c
                            \"model\":\"animal\"}, …]}],  what it is in 3D (optional)\n\c
 \"stacks\": [{\"template\": \"on(Block, Support)\",   a thing standing on another thing\n\c
              \"member_var\": \"Block\",               which argument names the thing\n\c
              \"support_var\": \"Support\",            which argument names what it stands on\n\c
              \"ground\": [\"table\"],                 what the piles stand on, if named\n\c
              \"members\": [{\"id\":\"a\"}, {\"id\":\"b\"}, …]}],\n\c
 \"spans\": [{\"template\": \"deal_with_goat(From, To)\",  a COMPOSITE EVENT\n\c
             \"member_var\": \"To\",                 which argument to put on the bar\n\c
             \"label\": \"crossing\"}]}\n\n\c
Choosing well is the part that needs you, and the choice is between five shapes:\n\n\c
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
- **Lamps**, when a fluent is simply true or false: `alerted`, `stopped`, \c
`in_station`. A gauge with its \"value_var\" LEFT OUT — \c
`{\"template\": \"alerted\", \"label\": \"alerted\"}` — is a lamp: its box is there \c
while the fluent holds and gone while it does not, under a caption that stays. This \c
is how a program whose state is a handful of flags gets drawn at all; do not try to \c
invent a value argument for one.\n\n\c
- **Spans**, for a **composite event** — an event the program defines as a sequence of \c
others, `deal_with_goat(From, To) from T1 to T2 if …`. That is an *act*: a thing with \c
a beginning and an end, and the only narrative shape a program can state. Each gets a \c
lane of its own and one bar per occurrence, drawn from the act's own start to its own \c
end and kept on the chart afterwards, so the lanes read as a history of what the run \c
did. Use this ONLY for composite events (§7 of the reference), never for a fluent.\n\n\c
Leave out anything that is none of the five. A plan with fewer, right things in it \c
beats one that forces a counter into a container. A program can need more than one \c
shape at once; it can need only one.\n\n\c
You are not asked which fluents are **derived** (defined by a rule rather than set by \c
an event), nor what order to put things in: the program says both, and the layout \c
reads them off it — a derived fluent is drawn as an outline, and the row follows the \c
order the rules mention things in.\n\n\c
**Show everything that moves.** A picture of a program is of what CHANGES in it: every \c
fluent listed under WHAT THE RUN DOES below must appear in the plan — as a layer, a \c
stack, a gauge or a lamp — and a plan that leaves one out will be handed back to you \c
saying which. A fluent that never changes is backdrop: draw it only if it helps.\n\n\c
~w\c
The layout finishes the job: you do not need to `finish` afterwards.",
	       [Label, Kind, Focus]).

/*  What the run does, computed rather than guessed.
 *
 *  A picture of a program is a picture of what CHANGES in it, and which
 *  fluents change is not something to read off the source: `underground.lps`
 *  has five, and the animation that came back drew two of them — the two whose
 *  names happened to be in the sentence the reader had typed.
 *
 *  The engine knows the answer exactly. `lps_scene_focus/3` (lps_explain.pl,
 *  AnimationPlan.md §5) reads it off the trace: the fluents that tell the
 *  states apart, the cycles worth a frame, and the states the run comes back
 *  to. That is put in front of the model before it plans, beside the rule that
 *  says to cover it (plan_prompt/5) and the check that hands an incomplete
 *  plan back (layout_gaps/4). The same focus keys the scene strip the IDE
 *  draws (§7), so the picture and the prompt cannot disagree about what
 *  matters.
 */
focus_material(Ctx, Buf, Material) :-
	(   catch(scene_focus(Ctx, Buf, focus(Disc, KFs, Loops), Steady, Max), _, fail),
	    Disc \== []
	->  %  capped: a program with fifty fluents would otherwise push the
	    %  reference and the icon catalogue out of a small model's context
	    cap(20, Disc, Shown, More),
	    maplist(disc_line, Shown, DLs0),
	    ( More == 0 -> DLs = DLs0 ; append(DLs0, ['  … and more'], DLs) ),
	    atomic_list_concat(DLs, '\n', DT),
	    (   Steady == []
	    ->  ST = ""
	    ;   cap(20, Steady, St2, _),
		maplist(pi_name, St2, SNs),
		atomic_list_concat(SNs, ', ', SN),
		format(string(ST), "These never change, so they are backdrop at most: ~w\n", [SN])
	    ),
	    keyframe_line(KFs, Loops, Max, KT),
	    format(string(Material),
		   "=== WHAT THE RUN DOES (it was run; this is read off its trace) ===\n\c
These fluents tell its states apart, and the picture must show every one of them:\n\c
~w\n~w~w\n", [DT, ST, KT])
	;   Material = ""
	).

cap(N, List, Shown, More) :-
	length(List, L),
	(   L > N
	->  length(Shown, N), append(Shown, Rest, List), length(Rest, More)
	;   Shown = List, More = 0
	).

disc_line(disc(Name/Arity, Example, N, Kind), Line) :-
	( Kind == derived -> D = "  (derived: a rule defines it — no event sets it)" ; D = "" ),
	format(atom(Line), "  ~w/~w  — ~w instance(s), e.g. ~q~w",
	       [Name, Arity, N, Example, D]).

pi_name(Name/Arity, S) :- format(atom(S), "~w/~w", [Name, Arity]).

keyframe_line([], _, _, "") :- !.
keyframe_line(KFs, Loops, Max, Line) :-
	findall(C, member(kf(C, _, _), KFs), Cs),
	cap(12, Cs, Shown, More),
	atomic_list_concat(Shown, ', ', CT),
	( More == 0 -> Tail = "" ; format(string(Tail), " and ~w more", [More]) ),
	length(KFs, NK), length(Loops, NL),
	(   NL > 0
	->  format(string(LT), ", and it comes back to ~w of them", [NL])
	;   LT = ""
	),
	format(string(Line),
	       "The run is ~w cycles long but has only ~w moments worth a picture — \c
cycles ~w~w~w. Draw for those.\n", [Max, NK, CT, Tail, LT]).

%!	scene_focus(+Ctx, +Buf, -Focus, -Steady, -Max) is semidet.
%
%	The focus of a run of this buffer, plus the fluents that do NOT
%	discriminate (backdrop) and how long the run is. Fails when the program
%	does not compile or does not run — there is then nothing to say about
%	it, and the prompt simply does without the section.
scene_focus(Ctx, Buf, Focus, Steady, Max) :-
	with_compiled(Ctx, Buf, _, P),
	P \== none,
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _),
	lps_session_focus(S, Focus),
	Focus = focus(Disc, _, _),
	lps_session_timeline(S, timeline(Max, Lanes, _, _)),
	findall(K, ( member(lane(F, _), Lanes), functor(F, N, A), K = N/A ), Ks0),
	sort(Ks0, Ks),
	findall(K, ( member(K, Ks), \+ memberchk(disc(K, _, _, _), Disc) ), Steady).

%!	layout_gaps(+Ctx, +Buf, +Plan, -Gaps:list) is det.
%
%	The fluents that tell the run's states apart and that the plan does not
%	draw, by name. The plan names its fluents as templates (`loc(Object,
%	Where)`), so the comparison is on the functor and arity the template
%	reads as.
layout_gaps(Ctx, Buf, Plan, Gaps) :-
	(   catch(scene_focus(Ctx, Buf, focus(Disc, _, _), _, _), _, fail)
	->  findall(K, ( member(disc(K, _, _, _), Disc), \+ plan_covers(Plan, K) ), Gaps)
	;   Gaps = []
	).

plan_covers(Plan, Name/Arity) :-
	member(Field, [layers, gauges, stacks, spans]),
	get_dict(Field, Plan, Items), is_list(Items),
	member(I, Items), is_dict(I),
	get_dict(template, I, T),
	catch(term_string(Tmpl, T), _, fail),
	callable(Tmpl),                    % `alerted` is an atom: a lamp, arity 0
	functor(Tmpl, Name, Arity), !.

/*  What the PROGRAM says about the plan's fluents, which the model is never
    asked for (AnimationPlan.md §6).

    Two things, and the program knows both exactly:

      * which of the plan's fluents are **intensional** — defined by a rule
	rather than set by an event. They are drawn as outlines, because a
	reader who takes one for a stored fluent goes looking for the event
	that set it, and there is none to find.
      * the order its **rules** mention its fluents in. Two fluents that appear
	in one rule belong side by side; one no rule mentions belongs at the
	end. Without this the row is in the order the model happened to list
	things in, which is the order it read them in, which is nothing.
*/
scene_options(Ctx, Buf, Plan, Options) :-
	(   catch(with_compiled(Ctx, Buf, _, P), _, fail), P \== none
	->  plan_templates(Plan, Tmpls),
	    findall(K,
		    ( member(T, Tmpls), catch(p_intensional(P, T), _, fail),
		      functor(T, N, A), K = N/A ),
		    D0),
	    sort(D0, Derived),
	    rule_order(P, Order),
	    Options = [derived(Derived), order(Order)]
	;   Options = []
	).

%	Every template the plan names, as a term.
plan_templates(Plan, Tmpls) :-
	findall(T,
		( member(Field, [layers, gauges, stacks, spans]),
		  get_dict(Field, Plan, Items), is_list(Items),
		  member(I, Items), is_dict(I),
		  get_dict(template, I, TS),
		  catch(term_string(T, TS), _, fail),
		  callable(T) ),
		Tmpls).

%!	rule_order(+Program, -Keys) is det.
%
%	The program's fluents as its rules mention them: each rule contributes
%	its own fluents in the order they appear in it, rules in source order,
%	first mention winning. Fluents no rule mentions come last.
rule_order(P, Order) :-
	fluent_keys(P, Keys),
	findall(Ks, ( rule_term(P, T), keys_in(Keys, T, Ks), Ks \== [] ), Groups),
	append(Groups, Seq0),
	append(Seq0, Keys, Seq),
	dedup_first(Seq, Order).

fluent_keys(P, Keys) :-
	findall(N/A, ( p_fluent(P, F), functor(F, N, A) ), Ks),
	sort(Ks, Keys).

rule_term(P, rule(A, C)) :- p_reactive_rules(P, Rs), member(reactive_rule(A, C), Rs).
rule_term(P, law(E, F, C)) :- p_initiated(P, E, F, C).
rule_term(P, law(E, F, C)) :- p_terminated(P, E, F, C).
rule_term(P, law(E, F, C)) :- p_updated(P, E, F, _, C).
rule_term(P, int(H, B))    :- p_l_int(P, H, B).

%	The fluent keys a term mentions, in the order they appear in it.
keys_in(Keys, Term, Out) :-
	findall(K,
		( sub_term(Sub, Term), callable(Sub), \+ is_list(Sub),
		  functor(Sub, N, A), K = N/A, memberchk(K, Keys) ),
		L),
	dedup_first(L, Out).

dedup_first([], []).
dedup_first([X|Xs], [X|Out]) :-
	exclude(==(X), Xs, Rest),
	dedup_first(Rest, Out).

		 /*******************************
		 *	   the prompt		*
		 *******************************/

/* The Light assistant has no file tools, so everything it needs is inlined:
   the language reference, a couple of worked examples, the tool protocol and
   the program itself. docs/user/reference/lps.md is written to be inlined — that is
   why §I.10.7 schedules it *before* this milestone.
*/
system_prompt(Ctx, Buf, Extra, Req, Prompt) :-
	reference_for(Extra, Syntax),
	extra_material(Extra, Req, Material),
	program_material(Ctx, Buf, Program),
	language_rules(Ctx, Rules),
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
  {\"action\":\"docs\", \"query\":\"a few keywords\"}   search the user documentation~n\c
  {\"action\":\"finish\", \"explanation\":\"markdown\", \"new_content\":\"…\"}  done~n~n\c
Rules:~n\c
- `new_content` is always the WHOLE program, never a fragment or a diff.~n\c
- After an `edit`, `analyse` before you `finish`. Never finish on a program you~n\c
  have not compiled. If the diagnostics are not empty, fix them and try again.~n\c
- Keep the user's own comments and formatting; change as little as you can.~n\c
- If you cannot do what was asked, `finish` and say so plainly.~n\c
- If the person only asks a question (about LPS, Logical English for LPS, the IDE,~n\c
  or this program) and nothing needs to change, `finish` as soon as you can answer,~n\c
  without `new_content`. When the documentation answers it, end the explanation~n\c
  with at most three Markdown links to it, from `docs` or from the section~n\c
  DOCUMENTATION THAT MAY HELP, with the URLs exactly as given. Never invent one.~n\c
~w~n\c
=== THE LANGUAGE ===~n~w~n~n\c
~w~n\c
~w",
	       [Rules, Syntax, Material, Program]).

/*  What the model is shown of the buffer, and in Logical English's case that
 *  is three texts rather than one.
 *
 *  The English is what it may edit. The *generated* internal program is what
 *  `analyse` and `run` actually see, and it is the only place the predicate
 *  names appear — `the light in a room is a setting` becomes `light(Room,
 *  Setting)`, and a plan naming the template as written in English names
 *  nothing the engine has. The companion is the third, because a plan replaces
 *  its display clauses and the model should know what it is replacing.
 */
program_material(ctx(le, Name, CName), b(Content, Companion), Text) :- !,
	le_generated(Content, Name, Generated),
	(   Companion == ""
	->  format(string(CompText),
		   "=== THE COMPANION `~w` (empty — there is no companion file yet) ===~n",
		   [CName])
	;   format(string(CompText),
		   "=== THE COMPANION `~w` (LPS external syntax; this is where \c
Prolog goes) ===~n~w~n", [CName, Companion])
	),
	format(string(Text),
	       "=== THE DOCUMENT `~w` (Logical English — this is what `edit` replaces) ===~n\c
~w~n~n\c
=== WHAT IT COMPILES TO (LPS internal syntax; `analyse` and `run` see this, \c
and a plan must use THESE predicate names) ===~n~w~n~n~w",
	       [Name, Content, Generated, CompText]).
program_material(_, b(Content, _), Text) :-
	format(string(Text),
	       "=== THE PROGRAM (this is what `analyse` and `run` see) ===~n~w~n",
	       [Content]).

le_generated(Content, Name, Text) :-
	(   catch(lps_le_translate_text(Content, Name, T, _, _), _, fail),
	    T \== ""
	->  Text = T
	;   Text = "(this document does not currently translate — `analyse` says why)"
	).

%	The one rule a Logical English buffer adds, and it is worth its four
%	lines: an assistant that writes a Prolog clause into an English document
%	breaks the document, and the person who pressed a button on the toolbar
%	is left with a file that no longer compiles.
language_rules(ctx(le, _, CName), Rules) :- !,
	format(string(Rules),
	       "- This buffer is a **Logical English document**. `edit` replaces the \c
ENGLISH.~n\c
  NEVER write Prolog or LPS syntax into it — no `display(…)`, no `:-`, no clause~n\c
  ending in a full stop. LE2 reads one as a malformed section and the document~n\c
  stops compiling.~n\c
- Prolog belongs in the companion file `~w`, which compiles together with the~n\c
  document. `layout` writes the display clauses there for you; to change it~n\c
  yourself use {\"action\":\"edit\", \"file\":\"companion\", \"new_content\":\"…\"}.~n\c
- What the document compiles to is shown below in INTERNAL syntax, where the~n\c
  declarations read `fluents([f(A,B)])` and `initial_state([…])` and a law reads~n\c
  `initiated(happens(E,T1,T2), F, [])`. Read the predicate names from there.~n",
	       [CName]).
language_rules(_, "").

/*  What the model needs in order to *plan*, which is a different list from what
    it needed in order to *write* display clauses. The shape vocabulary and the
    coordinate conventions are gone: it does not write either. What is left is
    the reading — which fluent is which shape — and the icon catalogue, which is
    the one place a plan still names something concrete. */
extra_material(animate2d, Req, Material) :- !,
	icon_catalogue(Req, Icons),
	library_catalogue('/ui/patterns/manifest.json', patterns, Fills),
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
load — prefer one to a colour wherever a thing has an obvious picture:~n~w~n~n\c
A member, a gauge, a lamp or a span may also take a `pattern`, which fills its~n\c
surface. A fill says what a surface is LIKE where an icon says what a thing IS,~n\c
and it is the one distinction a scene of flat rectangles cannot otherwise make:~n\c
hatched for unavailable, bricks for built, waves for water. The fill takes the~n\c
thing's own colour, so it never fights the palette. The library:~n~w~n",
	       [Icons, Fills]).
/*  Both animate buttons get the same material now, because both go through the
    plan. What the model still has to choose is which *shape* each fluent is and
    what each thing looks like, and the icon catalogue is what makes the second
    of those possible without inventing a URL. */
extra_material(animate3d, Req, Material) :- !,
	extra_material(animate2d, Req, M0),
	library_catalogue('/ui/models3d/manifest.json', models, Objects),
	format(string(Three),
	       "\n=== IN THREE DIMENSIONS ===\nThe same plan is laid out standing up: the \c
container grid becomes a floor plan, things stand on their slab, and a stack is a \c
tower. The ground plane, the camera and the light are computed and written for you — \c
do not write a `display3d(timeless, …)` yourself, and do not write coordinates. \c
Icons are a 2D idea and are ignored here; `color` and `pattern` on a member are not.\n\n\c
Here a member may take a `model` instead of an icon: a named object, built from \c
primitives in the thing's own colour, which is what makes a floor plan of boxes into a \c
scene. Use one wherever a thing is one of these, and leave it out otherwise — a member \c
with no model is a plain box, which is no worse than it was.\n~w\n", [Objects]),
	string_concat(M0, Three, Material).
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

/*  The pattern and object catalogues, read from their manifests the way the
    icons are: the browser has its own copy, a curl caller does not, and the
    assistant should not be less capable for being driven from a script. */
library_catalogue(Rel, Key, Text) :-
	(   catalogue_text(Rel, Key, T)
	->  Text = T
	;   Text = "(this library is unavailable on this server)"
	).

catalogue_text(Rel, Key, Text) :-
	lps_root_dir(Root),
	atomic_list_concat([Root, Rel], Path),
	exists_file(Path),
	setup_call_cleanup(open(Path, read, In, [encoding(utf8)]),
			   json_read_dict(In, D),
			   close(In)),
	get_dict(Key, D, Items),
	findall(S, ( member(I, Items),
		     get_dict(name, I, N), get_dict(desc, I, De),
		     ( get_dict(concepts, I, Cs) -> true ; Cs = [] ),
		     atomic_list_concat(Cs, ', ', CS),
		     format(atom(S), "  ~w — ~w (~w)", [N, De, CS]) ),
		Lines),
	Lines \== [],
	atomic_list_concat(Lines, '\n', Text).

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

/*  How much of the language reference to inline, and why not all of it.
 *
 *  A typed question can be about anything, so it gets the whole thing. The two
 *  animate buttons cannot: their whole job is to *read* a program and describe
 *  what is in the picture, and they are one turn long. Sending them all of
 *  `lps_summary.md` sent 30 kB — about 7,700 tokens — of which the largest
 *  single piece was §18's table of `display/2` shapes and properties, which
 *  the model has had no use for since it stopped writing display clauses.
 *
 *  That is not merely wasteful. With the program and the icon catalogue on top
 *  it came to about 11,000 tokens, and an 8,192-token model — most of Groq's
 *  catalogue — refused the request outright. The reading sections come to
 *  about a fifth of that.
 *
 *  Selected from the file by heading rather than copied into a second string:
 *  a duplicate of the language reference maintained here would be wrong within
 *  a month, and wrong in the direction of teaching the model a language the
 *  compiler no longer speaks.
 */
reference_for(Extra, Text) :-
	animate_command(Extra), !,
	lps_doc('user/reference/lps.md', Whole),
	reading_sections(Wanted),
	doc_sections(Whole, Wanted, Text).
reference_for(_, Text) :- lps_doc('user/reference/lps.md', Text).

animate_command(animate2d).
animate_command(animate3d).

%	What you need in order to read a program and say what it is about: what a
%	program is, what it declares, what it starts as, what moves, what is
%	computed rather than stored, and how time is written.
reading_sections(['## 1.', '## 3.', '## 4.', '## 5.', '## 8.', '## 11.']).

%!	doc_sections(+Markdown, +Prefixes, -Text) is det.
%
%	The `##` sections whose heading starts with one of Prefixes, in the order
%	the document has them.
doc_sections(Markdown, Prefixes, Text) :-
	split_string(Markdown, "\n", "", Lines),
	sections_(Lines, Prefixes, no, [], Rev),
	reverse(Rev, Kept),
	atomic_list_concat(Kept, '\n', Text0),
	atom_string(Text0, Text).

sections_([], _, _, Acc, Acc).
sections_([L|Ls], Prefixes, In, Acc, Out) :-
	(   sub_string(L, 0, 3, _, "## ")
	->  ( member(P, Prefixes), sub_string(L, 0, _, _, P) -> In1 = yes ; In1 = no )
	;   In1 = In
	),
	( In1 == yes -> Acc1 = [L|Acc] ; Acc1 = Acc ),
	sections_(Ls, Prefixes, In1, Acc1, Out).

example_text(Name, Text) :-
	(   current_predicate(lps_http:example_source/2),
	    lps_http:example_source(Name, T)
	->  Text = T
	;   Text = ""
	).

/*  The user documentation searched for a request, as a section of the
 *  prompt: "" when nothing in it fits. */
docs_material(Request, Block) :-
	docs_root(Root),
	docs_search_material(Root, Request, [limit(5), slug(lps2)], Lines),
	(   Lines == ""
	->  Block = ""
	;   format(string(Block),
		   "~n=== DOCUMENTATION THAT MAY HELP ===~n\c
The user documentation of this server was searched for the request, and these \c
sections came up (links relative to this server):~n~w~n\c
If the request is a question about LPS, Logical English for LPS or the IDE, answer \c
it briefly and end the explanation with at most three of these links, only those \c
that really answer it, with the URL exactly as given. If the request asks for a \c
change, or none of them fits, add no links.~n",
		   [Lines])
	).

docs_root(Root) :-
	lps_root_dir(Dir),
	directory_file_path(Dir, 'docs/user', Root).

lps_root_dir(Root) :-
	module_property(lps_assistant, file(F)),
	file_directory_name(F, Dir), file_directory_name(Dir, Src),
	file_directory_name(Src, Root).

		 /*******************************
		 *	    the loop		*
		 *******************************/

agent_loop(Id, _, _, _, _, Buf, Step, Expl, Buf) :-
	max_steps(Max), Step >= Max, !,
	format(string(Expl),
	       "I used all ~w of my steps without finishing, so the program is as I \c
last left it. Ask again — I will start from where this left the buffer — or ask \c
for a smaller piece of the job.", [Max]),
	progress(Id, "step limit reached").
agent_loop(Id, _, _, _, _, Buf, _, Expl, Buf) :-
	interrupted(Id), !,
	Expl = "Interrupted.".
agent_loop(Id, Ctx, Model, Keys, Messages, Buf, Step, Expl, Final) :-
	model_provider(Model, Provider),
	(   have_key(Provider, Keys, Key)
	->  true
	;   throw(error(no_key(Provider),
			context(lps_assistant, 'no API key for that provider')))
	),
	check_fits(Model, Messages),
	Buf = b(Program, _),
	output_budget(Model, Program, Messages, MaxOut),
	llm_request(Model, Messages, Reply, [api_key(Key), max_tokens(MaxOut), timeout(180)]),
	(   parse_action(Reply, Action)
	->  handle(Id, Ctx, Action, Buf, Buf1, Result, Done, Expl0),
	    (	Done == true
	    ->	Expl = Expl0, Final = Buf1
	    ;	format(string(Obs), "~w", [Result]),
		append(Messages, [role(assistant, Reply), role(user, Obs)], Messages1),
		Step1 is Step + 1,
		agent_loop(Id, Ctx, Model, Keys, Messages1, Buf1, Step1, Expl, Final)
	    )
	;   append(Messages, [role(assistant, Reply),
			      role(user, "Reply with exactly one JSON action object.")], Messages1),
	    Step1 is Step + 1,
	    progress(Id, "no action in that reply; nudging"),
	    agent_loop(Id, Ctx, Model, Keys, Messages1, Buf, Step1, Expl, Final)
	).

model_provider(Model, Provider) :-
	( llm_model(Model, Provider, _) -> true ; Provider = openai ).

/*  Two guards around a limit somebody else enforces.
 *
 *  A model with an 8,192-token window — which is most of what Groq hosts —
 *  used to be offered in the picker like any other, accept the job, and come
 *  back with "your messages resulted in 12543 tokens", a sentence about the
 *  provider's arithmetic that tells the user nothing they can act on. The
 *  prompt is much smaller now (see reference_for/2), but "much smaller" is not
 *  a guarantee: a long program can still overrun a small model.
 *
 *  So: refuse before sending, name the size and the window, and name a model
 *  that would fit — the picker's own list, so the advice is about this
 *  server's keys and not about models in general.
 *
 *  The estimate is characters over four. It does not need to be better than
 *  that: it is used to decide between "certainly too big" and "probably fine",
 *  and the 15% margin is wider than the error.
 */
check_fits(Model, Messages) :-
	(   catch(lps_models:model_window(Model, Window), _, fail),
	    estimate_tokens(Messages, Est),
	    Est * 100 > Window * 85
	->  bigger_models(Window, Alternatives),
	    format(atom(M),
		   'this request is about ~w tokens and ~w can be told at most ~w \c
at once, so the provider would refuse it. ~w',
		   [Est, Model, Window, Alternatives]),
	    throw(error(context_too_small(Model), context(lps_assistant, M)))
	;   true
	).

%	Room for the answer, within what the model can hold. Asking for 8,000
%	completion tokens from an 8,192-token model is a second way to be refused
%	by the same limit, and one the shorter prompt does not fix.
output_budget(Model, Program, Messages, MaxOut) :-
	%  The largest honest answer is a `finish` carrying the whole program
	%  back, so **the program** is the scale — not the prompt, most of which
	%  is reference material that will not be echoed, and not a round number
	%  chosen once. A flat 8,000 was both far more than any reply needs and,
	%  on a model that counts the reservation against its context (OpenAI
	%  does, and says so), a second way to be refused by a limit the prompt
	%  already fits inside: 5,200 tokens of prompt plus an 8,000-token
	%  reservation overruns an 8,192-token model by half again.
	estimate_tokens(Messages, Est),
	text_length(Program, PL),
	Want is max(1500, min(8000, (PL // 4) * 2 + 1200)),
	(   catch(lps_models:model_window(Model, Window), _, fail)
	->  Room is max(512, Window - Est - 256),
	    (   catch(lps_models:model_max_output(Model, Hard), _, fail)
	    ->  MaxOut is min(Want, min(Room, Hard))
	    ;   MaxOut is min(Want, Room)
	    )
	;   MaxOut = Want
	).

estimate_tokens(Messages, Tokens) :-
	findall(L, ( member(role(_, C), Messages), text_length(C, L) ), Ls),
	sum_list(Ls, Chars),
	Tokens is Chars // 4.

text_length(C, L) :- ( string(C) ; atom(C) ), !, atom_length(C, L).
text_length(C, L) :- term_to_atom(C, A), atom_length(A, L).

%	Something on this server that would fit, named rather than described.
bigger_models(Window, Text) :-
	(   catch(assistant_models(Ms), _, fail),
	    findall(N-W, ( member(M, Ms), get_dict(name, M, N),
			   get_dict(window, M, W), integer(W), W > Window * 2 ), Big),
	    Big \== []
	->  sort(2, @>=, Big, Sorted),
	    length(Prefix, 3), ( append(Prefix, _, Sorted) -> true ; Prefix = Sorted ),
	    findall(S, ( member(N2-W2, Prefix), format(atom(S), '~w (~w)', [N2, W2]) ), Names),
	    atomic_list_concat(Names, ', ', NT),
	    format(atom(Text), 'Choose a model with more room — this server offers ~w.', [NT])
	;   Text = 'Choose a model with a larger context window, or shorten the program.'
	).

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

handle(Id, Ctx, Action, Buf, Buf, Result, false, "") :-
	get_dict(action, Action, "analyse"), !,
	progress(Id, "analyse"),
	tool_analyse(Ctx, Buf, Result).
handle(Id, Ctx, Action, Buf, Buf, Result, false, "") :-
	get_dict(action, Action, "run"), !,
	progress(Id, "run"),
	( get_dict(cycles, Action, N), integer(N) -> Cycles = N ; Cycles = 0 ),
	tool_run(Ctx, Buf, Cycles, Result).
/*  The second stage of scene generation (§I.10.4e, lps_scene.pl). The model
 *  hands over a *plan* — containers, things, which template puts a thing in a
 *  container — and this replaces the program's display clauses with ones whose
 *  geometry was computed rather than imagined. The model never writes a
 *  coordinate, which is the whole point: it was the only part of the job it was
 *  reliably bad at. */
handle(Id, Ctx, Action, Buf, New, Result, Finished, Expl) :-
	get_dict(action, Action, "layout"), !,
	progress(Id, "layout"),
	%  The same plan grammar in both dimensions (§I.10.4e). `kind` says which
	%  declaration to write; only that one is replaced, so a program can carry
	%  a 2D scene and a 3D one at the same time and "Animate in 3D" does not
	%  quietly delete the picture the user already had.
	( get_dict(kind, Action, "3d") -> Kind = threed, Decl = display3d
	; Kind = twod, Decl = display ),
	(   get_dict(plan, Action, Plan), is_dict(Plan)
	->  scene_options(Ctx, Buf, Plan, Options),
	    scene_clauses(Plan, Kind, Options, Clauses, Diags),
	    (   Clauses == ""
	    ->  New = Buf, Result = "", Finished = true,
		findall(L, ( member(D, Diags), diag_line(D, L) ), Ls),
		atomic_list_concat(Ls, '\n', LT),
		format(string(Expl), "I could not lay that plan out.~n~w", [LT])
	    ;   %  Which of the two texts the clauses go into. Prolog in a
		%  Logical English document is not a bad edit but an
		%  impossible one, so for a `.le` buffer the target is its
		%  companion — the file the §7 rule exists to provide.
		write_display(Ctx, Buf, Decl, Clauses, New, Where),
		tool_analyse(Ctx, New, A),
		%  Drawn — but of everything that moves? A plan that leaves a
		%  changing fluent out is a picture with the plot missing, and
		%  the model cannot tell which those are by reading the source
		%  (focus_material/3 says why). So it is handed back, once,
		%  with the names; it may plan again or finish and say why not.
		layout_gaps(Ctx, New, Plan, Gaps),
		(   Gaps == []
		->  Result = "", Finished = true,
		    plan_summary(Plan, Decl, Where, Diags, A, Expl)
		;   Finished = false, Expl = "",
		    maplist(motion_name_of, Gaps, GNs),
		    atomic_list_concat(GNs, ', ', GT),
		    format(string(Result),
			   "layout: written to ~w, but it does not draw these fluents, \c
which change during the run: ~w.~nSend another `layout` whose plan covers them too \c
(a value gets a gauge, a true-or-false fluent gets a lamp — a gauge with no \c
`value_var` — a thing in a place gets a layer, a thing on a thing gets a stack). If one of them is genuinely not worth drawing, `finish` and say which and why.",
			   [Where, GT])
		)
	    )
	;   New = Buf, Result = "", Finished = true,
	    Expl = "I need a `plan` object to lay out; nothing was changed."
	).
handle(Id, Ctx, Action, Buf, Buf, Result, false, "") :-
	get_dict(action, Action, "scene"), !,
	progress(Id, "scene"),
	( get_dict(cycle, Action, C), integer(C) -> Cycle = C ; Cycle = -1 ),
	( get_dict(kind, Action, "3d") -> Decl = display3d ; Decl = display ),
	tool_scene(Ctx, Buf, Cycle, Decl, Result).
handle(Id, Ctx, Action, Buf, Buf, Result, false, "") :-
	get_dict(action, Action, "explain"), !,
	progress(Id, "explain"),
	( get_dict(question, Action, Q) -> true ; Q = "why_not(happened(x), 1)" ),
	tool_explain(Ctx, Buf, Q, Result).
handle(Id, Ctx, Action, Buf, New, Result, false, "") :-
	get_dict(action, Action, "edit"), !,
	get_dict(new_content, Action, Content),
	progress(Id, "edit"),
	edit_target(Ctx, Action, Content, Buf, New, Refusal),
	(   Refusal == none
	->  tool_analyse(Ctx, New, Result)
	;   Result = Refusal
	).
handle(_Id, _Ctx, Action, b(Program, Comp), b(Final, Comp), "", true, Expl) :-
	get_dict(action, Action, "finish"), !,
	( get_dict(explanation, Action, Expl) -> true ; Expl = "Done." ),
	( get_dict(new_content, Action, N), string(N), N \== "" -> Final = N ; Final = Program ).
handle(Id, _Ctx, Action, Buf, Buf, Result, false, "") :-
	get_dict(action, Action, "docs"), !,
	( get_dict(query, Action, Q), string(Q) -> true ; Q = "" ),
	progress(Id, "docs"),
	docs_root(Root),
	docs_search_answer(Root, Q, [slug(lps2)], Result).
handle(_, _, _, B, B, "Unknown action. Use analyse, run, explain, docs, edit or finish.", false, "").

motion_name_of(Name/Arity, S) :- !, format(atom(S), "~w/~w", [Name, Arity]).
motion_name_of(X, X).

%!	write_display(+Ctx, +Buf, +Decl, +Clauses, -New, -Where) is det.
%
%	Replace one declaration's clauses, in the text that may hold them.
%	Where names the file it happened in, for the summary the user reads.
write_display(ctx(le, Name, CName), b(Content, Companion), Decl, Clauses,
	      b(Content, New), CName) :- !,
	strip_display(Companion, Decl, Stripped),
	%  A companion that did not exist starts here rather than with a blank
	%  line: the editor opens a tab on whatever comes back, and a file whose
	%  first line is empty reads as one somebody forgot to finish.
	(   normalize_space(atom(''), Stripped)
	->  format(string(New), "% The visual mapping for ~w, in LPS external syntax.~n\c
% ~w and ~w compile together (docs/user/reference/le-for-lps.md §7).~n~n~w",
		   [Name, Name, CName, Clauses])
	;   string_concat(Stripped, "\n\n", P1),
	    string_concat(P1, Clauses, New)
	).
write_display(ctx(_, Name, _), b(Content, Companion), Decl, Clauses,
	      b(New, Companion), Name) :-
	strip_display(Content, Decl, Stripped),
	string_concat(Stripped, "\n\n", P1),
	string_concat(P1, Clauses, New).

/*  Which text an `edit` replaces — and, for a Logical English document, whether
 *  it may.
 *
 *  The prompt says the rule; this enforces it, because a model that has been
 *  told once and asked to write display clauses will still reach for the
 *  buffer in front of it. The check is narrow on purpose: it looks for the
 *  clause heads *we* generate, and it answers with the action that would have
 *  worked rather than with a refusal.
 */
%	Only the companion changes; the document is left exactly as it was.
edit_target(ctx(le, _, _), Action, Content, b(Doc, _), b(Doc, Content), none) :-
	get_dict(file, Action, "companion"), !.
edit_target(ctx(le, _, CName), _Action, Content, b(Doc, Comp), b(Doc, Comp), Refusal) :-
	prolog_in_english(Content), !,
	format(string(Refusal),
	       "refused: that `new_content` puts Prolog clauses into the Logical \c
English document, which LE2 reads as a malformed section. Display clauses and any \c
other Prolog go in `~w` — either ask for a {\"action\":\"layout\"}, or edit the \c
companion with {\"action\":\"edit\", \"file\":\"companion\", \"new_content\":\"…\"}. \c
Nothing was changed.", [CName]).
edit_target(_, _, Content, b(_, Comp), b(Content, Comp), none).

%	A line that begins a clause we would have generated. Not a Prolog
%	parser: the English can contain a full stop and an opening bracket
%	without being Prolog, and this has to be wrong in the safe direction.
prolog_in_english(Content) :-
	split_string(Content, "\n", "", Lines),
	member(L, Lines),
	( sub_string(L, 0, _, _, "display(")
	; sub_string(L, 0, _, _, "display3d(")
	; sub_string(L, 0, _, _, "lps_slot(")
	; sub_string(L, 0, _, _, "lps_look(")
	), !.

/* The tools are the panes' own operations, called in process. A model that
   asks "does this compile?" gets the same answer the editor's problem strip
   shows, because it is the same call. */
tool_analyse(Ctx, Buf, Result) :-
	with_compiled(Ctx, Buf, Diags, _),
	(   Diags == []
	->  Result = "analyse: no problems."
	;   findall(S, ( member(D, Diags), diag_line(D, S) ), Lines),
	    atomic_list_concat(Lines, '\n', Body),
	    format(string(Result), "analyse:~n~w", [Body])
	).

diag_line(diag(Sev, Code, Pos, Msg, _), S) :-
	( Pos = src(_, Line, _, _) -> true ; Line = 0 ),
	format(string(S), "  ~w line ~w: ~w [~w]", [Sev, Line, Msg, Code]).

tool_run(Ctx, Buf, Cycles, Result) :-
	with_compiled(Ctx, Buf, Diags, P),
	(   P == none
	->  tool_analyse(Ctx, Buf, Result)
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
tool_scene(Ctx, Buf, Cycle0, Decl, Result) :-
	with_compiled(Ctx, Buf, _, P),
	(   P == none
	->  tool_analyse(Ctx, Buf, Result)
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
helper_prefix(_,         "lps_style(").

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
plan_summary(Plan, Decl, Where, Diags, Analysis, Expl) :-
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
`~w` clauses in `~w`. The geometry is computed from the plan rather than written by \c
me: ~w.~n~n~w~w",
	       [NG, NM, Decl, Where, How, Analysis, Notes]).

trace_summary(Trace, Summary) :-
	findall(Line,
		( member(stage(events, C, Items), Trace), Items \== [],
		  format(atom(Line), "  cycle ~w: ~q", [C, Items]) ),
		Lines0),
	( Lines0 == [] -> Lines = ["  (no events)"] ; length(Lines0, N), N > 12 ->
	    length(Head, 12), append(Head, _, Lines0), append(Head, ["  …"], Lines) ; Lines = Lines0 ),
	atomic_list_concat(Lines, '\n', Summary).

tool_explain(Ctx, Buf, QuestionS, Result) :-
	with_compiled(Ctx, Buf, _, P),
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

/*  The buffer, compiled the way the editor would compile it.
 *
 *  Two paths, because there are two kinds of buffer. An LPS program is read
 *  and compiled. A Logical English document is *translated* by LE2 first and
 *  the generated internal syntax is what compiles — together with the `.lps`
 *  companion, which is where its display clauses and its Prolog live (§7 of
 *  docs/user/reference/le-for-lps.md). Reading the English as Prolog is what this used to
 *  do, and it made every tool the assistant has report a syntax error on line
 *  one of a document that compiles perfectly well.
 */
with_compiled(ctx(le, Name, CName), b(Content, Companion), Diags, P) :- !,
	lps_le_translate_text(Content, Name, Text, Prov, LeDiags),
	(   Text == ""
	->  Diags = LeDiags, P = none
	;   lps_le_program_terms(Text, Name, Prov, Companion, CName, Terms, ReadDiags),
	    lps_compile(terms(Terms), internal, [dc], P0, CDiags),
	    append([LeDiags, ReadDiags, CDiags], Diags),
	    ( diags_ok(Diags) -> P = P0 ; P = none )
	).
with_compiled(_, b(Program, _), Diags, P) :-
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
/*  An error we raised ourselves already carries a sentence written for the
    person reading it; `~q` on the whole term wraps that sentence in
    `error(context_too_small("allam-2-7b"), context(lps_assistant, '…'))` and
    makes it look like a crash. Take the sentence. */
message_to_text(error(_, context(_, Msg)), S) :-
	( string(Msg) ; atom(Msg) ), Msg \== '', !,
	atom_string(Msg, S).
message_to_text(E, S) :-
	(   catch(message_to_codes_(E, S0), _, fail)
	->  S = S0
	;   format(string(S), "~q", [E])
	).

api_error_message(P, M) :- is_dict(P), get_dict(error, P, E), !, api_error_message(E, M).
api_error_message(P, M) :- is_dict(P), get_dict(message, P, M), !.
api_error_message(P, M) :- string(P), !, M = P.

message_to_codes_(E, S) :- format(string(S), "~q", [E]).
