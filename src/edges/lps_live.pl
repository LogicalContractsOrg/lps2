/* lps_live.pl — perpetual, reactive sessions (M18, §II.0).
 *
 * Everything else in this system runs a program to an end and reads the trace
 * afterwards. That is the right default — it is what the conformance corpus
 * tests and what every pane displays — but it is not what an agent is. The old
 * engine could run a program in the background (`go(F, [background(Thread)])`)
 * and take events into it from outside (`inject_events/3`), and discarding its
 * session model discarded that mode without ever saying so.
 *
 * This is that mode, rebuilt on the session API:
 *
 *   * **unbounded cycles** — a program with no maxTime runs until it is told
 *     to stop, rather than until a default expires;
 *   * **wall-clock pacing at the edge** — the core still computes simulated
 *     time from the cycle number (§I.2.3, and the whole corpus rests on it);
 *     what happens here is that the driver *waits* so a cycle takes about the
 *     asked-for number of milliseconds. The clock stays out of src/core/;
 *   * **asynchronous observation** — events arriving between cycles are queued
 *     and consumed at the top of the next one, which is exactly
 *     lps_session_observe/3 plus a mailbox. Injection reports back what the
 *     cycle did with them, because "did my event get in?" is the question a
 *     client actually has;
 *   * **lifecycle** — start, pause, resume, step-once, stop, and the
 *     `lps_terminate` event, which is already in the engine's vocabulary;
 *   * **a bounded trace** — lps_session_trim/3, so a session that runs for a
 *     week does not keep every cycle's derivation forest.
 *
 * WASM: none of this file is WASM-compatible, and it does not need to be. The
 * *core* is what M11 cares about, and the core is untouched — a perpetual
 * session is a driver, a mailbox and a pacing policy. A browser build would
 * replace this thread with setInterval and lose nothing else.
 */

:- module(lps_live, [
	live_start/3,          % +Program, +Options, -Id
	live_status/2,         % +Id, -Dict
	live_observe/3,        % +Id, +EventStrings, -Result
	live_observe/4,        % +Id, +Channel, +EventStrings, -Result
	live_command/2,        % +Id, +pause|resume|stop|step
	live_scene/4,          % +Id, +Declaration, -Cycle, -Scene
	live_mouse_kinds/2,    % +Id, -Names
	live_flags/3,          % +Id, -Paused, -Status
	live_session/2,        % +Id, -Session
	live_allowed/3         % +Id, +Channel, -AllowedList
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../core/lps_ops').

:- dynamic live/2.               % Id, Dict
:- dynamic live_counter/1.
live_counter(0).

%	How many cycles of trace a live session keeps. Enough to explain what
%	just happened and to scrub the animation; not enough to run out of
%	memory overnight.
keep_cycles(400).

		 /*******************************
		 *	    lifecycle		*
		 *******************************/

live_start(Program, Options, Id) :-
	retract(live_counter(N)), N1 is N + 1, assertz(live_counter(N1)),
	format(atom(Id), 'live~w', [N1]),
	( memberchk(cycle_ms(Ms0), Options), number(Ms0) -> Ms = Ms0 ; Ms = 500 ),
	( memberchk(channels(Ch), Options) -> true ; Ch = _{} ),
	%  `unbounded`: a live session runs until it is stopped. Without it a
	%  program that declares no maxTime stops at the engine's batch default
	%  of twenty cycles — which looked, from the outside, exactly like
	%  clicking on an animation doing nothing after a while.
	lps_session_new(Program, [dc, unbounded], S0),
	assertz(live(Id, _{session: S0, status: running, paused: false,
			   inbox: [], log: [], cycle_ms: Ms, stop: false,
			   step_once: false, channels: Ch})),
	assertz(live_running(Id)),
	thread_create(live_driver(Id), _, [detached(true)]).

/*  A driver that says when it is gone.
 *
 *  `halt.` used to sit there for half a minute: SWI waits for threads at exit,
 *  and a detached driver asleep in `pace/2` is a thread. Setting every session's
 *  stop flag and waiting one pace-length is enough to make shutdown prompt, but
 *  only if there is something to wait *for* — hence the marker. */
:- dynamic live_running/1.

live_driver(Id) :-
	setup_call_cleanup(true, live_loop(Id), retractall(live_running(Id))).

%!	live_shutdown is det.
%
%	Stop every session and give the drivers a bounded moment to notice.
%	Registered as an `at_halt/1` hook, and safe to call twice.
live_shutdown :-
	forall(live(Id, _), catch(update(Id, [stop-true, status-stopped]), _, true)),
	wait_for_drivers(60).

wait_for_drivers(0) :- !.
wait_for_drivers(N) :-
	(   live_running(_)
	->  sleep(0.05), N1 is N - 1, wait_for_drivers(N1)
	;   true
	).

:- at_halt(lps_live:live_shutdown).

live_command(Id, pause)  :- update(Id, [paused-true]),  note(Id, "paused").
live_command(Id, resume) :- update(Id, [paused-false]), note(Id, "resumed").
live_command(Id, step)   :- update(Id, [step_once-true]).
live_command(Id, stop)   :- update(Id, [stop-true, status-stopped]), note(Id, "stopped").

%!	live_flags(+Id, -Paused, -Status) is det.
%
%	The two things a *viewer* needs, without draining the log the way
%	live_status/2 does — a second reader stealing the panel's feed is a bug
%	that only shows up when someone opens the pop-out window.
%	The parentheses around `false` are not decoration: it is an LPS prefix
%	operator (`false A, B.`), and lps_ops is imported here.
live_flags(Id, Paused, Status) :-
	(   live(Id, S)
	->  Paused = S.paused, format(string(Status), "~w", [S.status])
	;   Paused = (false), Status = "unknown"
	).

live_status(Id, Status) :-
	with_mutex(lps_live, live_status_(Id, Status)).

live_status_(Id, Status) :-
	(   live(Id, S)
	->  lps_session_time(S.session, T),
	    format(string(St), "~w", [S.status]),
	    %  The log is a tail read once, so a client that drains it has no way
	    %  back to "what is true now" — and that is the question a poller
	    %  usually has. Carry the state alongside it.
	    lps_session_state(S.session, Fluents),
	    maplist(term_to_text, Fluents, State),
	    Status = _{ok: true, cycle: T, status: St, paused: S.paused,
		       recent: S.log, state: State},
	    update(Id, [log-[]])          % the log is a tail, read once
	;   Status = _{ok: false, cycle: 0, status: "unknown", paused: false,
		       recent: ["no such live session"], state: []}
	).

live_session(Id, S) :- live(Id, D), S = D.session.

%!	live_allowed(+Id, +Channel, -Allowed) is semidet.
live_allowed(Id, Channel, Allowed) :-
	live(Id, S),
	get_dict(channels, S, Ch), is_dict(Ch),
	get_dict(Channel, Ch, Allowed), is_list(Allowed).

/*  Every change to a session's record is read-modify-write on one dynamic
    fact, and there are always at least two threads doing it: the driver
    stepping the session, and whatever HTTP worker is polling or observing. An
    unguarded interleaving loses a whole write — most visibly, a status poll
    clearing the log between the driver reading the dict and writing it back,
    which made a session's own actions vanish from its feed at random. SWI
    mutexes are recursive for the owning thread, so these compose. */
update(Id, Pairs) :- with_mutex(lps_live, update_(Id, Pairs)).

update_(Id, Pairs) :-
	(   live(Id, S)
	->  foldl([K-V, In, Out]>>put_dict(K, In, V, Out), Pairs, S, S1),
	    retractall(live(Id, _)), assertz(live(Id, S1))
	;   true
	).

note(Id, Line) :- with_mutex(lps_live, note_(Id, Line)).

note_(Id, Line) :-
	(   live(Id, S)
	->  append(S.log, [Line], L0),
	    ( length(L0, N), N > 60 -> length(L1, 60), append(_, L1, L0) ; L1 = L0 ),
	    retractall(live(Id, _)), assertz(live(Id, S.put(log, L1)))
	;   true
	).

		 /*******************************
		 *	   the driver		*
		 *******************************/

/* One cycle per tick, paced by the wall clock. `minCycleTime/1` in the program
   is honoured if it asks for something slower than the request did — a program
   that says it wants a second per cycle means it.
*/
live_loop(Id) :-
	(   live(Id, S)
	->  (   S.stop == true
	    ->	true
	    ;	S.paused == true, S.step_once \== true
	    ->	sleep(0.1), live_loop(Id)
	    ;	tick(Id, S), live_loop(Id)
	    )
	;   true
	).

tick(Id, S) :-
	get_time(T0),
	Session0 = S.session,
	(   lps_session_status(Session0, running)
	->  drain_inbox(Id, Session0, Session1),
	    catch(lps_session_step(Session1, Session2, Report), E,
		  ( format(string(M), "error: ~q", [E]), note(Id, M), Session2 = Session1,
		    Report = none )),
	    keep_cycles(K),
	    lps_session_trim(Session2, K, Session3),
	    update(Id, [session-Session3, step_once-false]),
	    report_line(Report, Line),
	    ( Line == "" -> true ; note(Id, Line) ),
	    lps_session_status(Session3, St),
	    (	St == running
	    ->	true
	    ;	update(Id, [status-St, stop-true]),
		format(string(M2), "ended: ~w", [St]), note(Id, M2)
	    )
	;   lps_session_status(Session0, St0),
	    update(Id, [status-St0, stop-true])
	),
	pace(S.cycle_ms, T0).

%	Wait out the rest of the requested period. This is the one place in the
%	system that reads the wall clock as a *rate*, and it is deliberately an
%	edge: §I.2.3's "time is injected, never read" is about the engine's own
%	notion of when things happen, which is untouched.
pace(Ms, T0) :-
	get_time(T1),
	Elapsed is (T1 - T0) * 1000,
	Wait is max(0, Ms - Elapsed) / 1000,
	( Wait > 0 -> sleep(Wait) ; true ).

report_line(none, "") :- !.
report_line(cycle(T, Events, _, _, Actions), Line) :-
	append(Events, Actions, All0),
	sort(All0, All),
	(   All == []
	->  Line = ""
	;   format(string(Line), "cycle ~w: ~q", [T, All])
	).
report_line(_, "").

		 /*******************************
		 *	    the mailbox		*
		 *******************************/

/* Events arriving between cycles wait here and are consumed at the top of the
   next one. `inject_events/3` upstream blocked until the running execution had
   accepted or rejected them; the same shape survives here as `live_observe/3`
   returning the cycle the events were queued for, so a client knows where to
   look for their effect.
*/
live_observe(Id, Strings, Result) :-
	live_observe(Id, any, Strings, Result).

/* §II.3(b), and it is the load-bearing safety property of the whole design:
   **no privileged event is ever sourced from the LLM channel**.

   A channel is a name an observation arrives under, and a channel may carry an
   allow-list of predicates. An event whose predicate is not on its channel's
   list is dropped and reported — not silently, because a client that thinks it
   observed something needs to know it did not.

   This is what makes "the model cannot fabricate approval" structural rather
   than procedural: `approved/1` is reachable only through a causal law fired by
   a real `approval/2` event, and `approval/2` is not on the llm channel's list.
   A confused or jailbroken model can propose the deletion all day.
*/
live_observe(Id, Channel, Strings, Result) :-
	with_mutex(lps_live, live_observe_(Id, Channel, Strings, Result)).

live_observe_(Id, Channel, Strings, Result) :-
	(   live(Id, S)
	->  maplist(parse_event, Strings, Events0),
	    exclude(==(none), Events0, Events1),
	    partition(allowed_on(S, Channel), Events1, Events, Refused),
	    (	Refused == []
	    ->	true
	    ;	format(string(RM), "REFUSED on channel ~w: ~q", [Channel, Refused]),
		note(Id, RM)
	    ),
	    append(S.inbox, Events, Inbox),
	    update(Id, [inbox-Inbox]),
	    lps_session_time(S.session, T),
	    Next is T + 1,
	    format(string(M), "queued for cycle ~w: ~q", [Next, Events]),
	    note(Id, M),
	    maplist(term_to_text, Refused, RefusedS),
	    Result = _{ok: true, queued: Next, refused: RefusedS}
	;   Result = _{ok: false, error: "no such live session"}
	).

term_to_text(T, S) :- format(string(S), "~q", [T]).

/*  The `mouse` channel is allow-listed by the *program*, not by configuration.
    A viewer may only inject the three interaction events, and only the ones the
    program actually defines — so opening an animation cannot become a way to
    fabricate a domain event, and a program that says nothing about the mouse is
    not made clickable behind its author's back. */
allowed_on(S, mouse, Event) :- !,
	functor(Event, Name, 3),
	memberchk(Name, [lps_mousedown, lps_mouseup, lps_mousedrag]),
	lps_session_program(S.session, P),
	defines_mouse(P, Name).
allowed_on(S, Channel, Event) :-
	(   get_dict(channels, S, Ch), is_dict(Ch), get_dict(Channel, Ch, Allowed), is_list(Allowed)
	->  functor(Event, Name, Arity),
	    format(atom(Spec), '~w/~w', [Name, Arity]),
	    ( memberchk(Spec, Allowed) -> true
	    ; atom_string(Name, NS), memberchk(NS, Allowed) -> true
	    ; atom_string(Spec, SS), memberchk(SS, Allowed) )
	;   true                              % no list for this channel: open
	).

/*  Events arrive as text, from a person typing or a model writing, and in
    SWI-Prolog 7 an unquoted `app.log` reads as the *compound* '.'(app, log)
    rather than as an atom. It then prints back as `app.log`, so the resulting
    term looks exactly right in every log and unifies with nothing — which is
    how examples/agent/demo.mjs came to report an approval that had approved a
    different file from the one requested.

    `allow_dot_in_atom` is the flag SWI provides for precisely this, and it is
    set only around the parse: inside the engine, `.`/2 means what Prolog says
    it means. Lists are unaffected.
*/
parse_event(S, Event) :-
	current_prolog_flag(allow_dot_in_atom, Old),
	setup_call_cleanup(
	    set_prolog_flag(allow_dot_in_atom, true),
	    catch(term_string(Event, S), _, Event = none),
	    set_prolog_flag(allow_dot_in_atom, Old)).

drain_inbox(Id, S0, S) :- with_mutex(lps_live, drain_inbox_(Id, S0, S)).

drain_inbox_(Id, S0, S) :-
	(   live(Id, D), D.inbox \== []
	->  lps_session_observe(S0, D.inbox, S),
	    update(Id, [inbox-[]])
	;   S = S0
	).

		 /*******************************
		 *	   live scenes		*
		 *******************************/

/* Whatever the session has reached, for the pop-out 2D and 3D viewers.
 *
 * Not `lps_session_time/2`: that is the cycle the session is *about to* run,
 * and the trace has no fluents for it yet — which showed up as a live view
 * drawing the backdrop and none of the objects. The last cycle with a state
 * recorded is the last one there is anything to draw.
 */
live_scene(Id, Decl, Cycle, Scene) :-
	live(Id, S),
	lps_session_trace(S.session, Trace),
	last_state_cycle(Trace, Cycle),
	lps_session_scene(S.session, Cycle, Decl, Scene).

%!	live_mouse_kinds(+Id, -Names) is det.
%
%	Which of `lps_mousedown/3`, `lps_mouseup/3` and `lps_mousedrag/3` this
%	program actually defines (§I.10.4d). A viewer attaches listeners only for
%	these, so a program that says nothing about the mouse is not made
%	clickable behind its author's back — and the allow-list on the `mouse`
%	channel is exactly this list, so an event it did not ask for cannot
%	arrive even if a page sends one.
live_mouse_kinds(Id, Names) :-
	(   live(Id, S)
	->  lps_session_program(S.session, P),
	    findall(N, ( member(N, [lps_mousedown, lps_mouseup, lps_mousedrag]),
			 defines_mouse(P, N) ), Names)
	;   Names = []
	).

defines_mouse(P, Name) :-
	functor(Ev, Name, 3),
	(   lps_program:p_user_event(P, Ev) -> true
	;   lps_program:p_user_action(P, Ev) -> true
	;   prog_module(P, M),
	    catch(( current_predicate(M:Name/3) ; clause(M:Ev, _) ), _, fail)
	).

last_state_cycle(Trace, Cycle) :-
	findall(C, member(stage(fluents, C, _), Trace), Cs),
	( Cs == [] -> Cycle = 0 ; max_list(Cs, Cycle) ).
