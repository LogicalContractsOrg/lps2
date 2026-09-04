/* lps_play.pl — playing a story: the player's channel, the turn, the parser
 * and the narrator (docs/InformPlan.md phase 2).
 *
 * A story is a Logical English program that includes examples/if/world.le.
 * The engine does not know it is a game: it takes command events and runs
 * cycles. Everything that makes it *feel* like one is here, at the edge:
 *
 *   * **the channel** — a typed line becomes a `cmd_*` event and nothing
 *     else. The events a player may inject are read off the program's own
 *     templates (the ones whose surface begins `the command is to`, and the
 *     `… is asked to …` ones for ordering a character about), so a raw
 *     `carries(player, key)` is refused the way a live session's LLM channel
 *     refuses an approval (§II.3);
 *   * **the turn** — `begin_turn` and the commands go in together, the
 *     session steps until a cycle in which nothing happens, `end_turn` goes
 *     in, and it steps to quiescence again. Inform's turn is the same shape:
 *     the action, then the every-turn rules and the timed events, then the
 *     prompt. Phase 0 found that a script cannot know how long a burst takes
 *     (Ogg's fetch is three cycles); a driver that waits can;
 *   * **the parser** — no grammar of its own. The command templates are the
 *     grammar: `the command is to put *a thing* into *a container*` is the
 *     pattern `put <thing> into <container>`, and a noun phrase resolves to a
 *     constant of the program by its words. Inform's `Understand` lines are
 *     a table of verb synonyms here (`get` for `take`, `x` for `examine`,
 *     `n` for `go north`). What the grammar does not take can go to the
 *     assistant's translator (phase 2(b)), which is offered the same list of
 *     events and nothing else;
 *   * **the narrator** — the trace rendered as prose. An action is told
 *     through its own template surface (`*a person* takes *a thing*` →
 *     "You take the lamp."), a `narrate/2` clause in the story's companion
 *     overrides it, and a *refusal* is told by asking the engine why the
 *     action did not happen: the denial's conditions, rendered through their
 *     templates, are the message ("You can't open the case: the case is
 *     locked."). Inform writes those messages by hand, one per check rule.
 *     `look`, `examine` and `inventory` are reports read off the state.
 *
 * Nothing here touches src/core/. A game is a session plus a dictionary, and
 * a turn is lps_session_observe/3 and lps_session_step/3 in a loop.
 */

:- module(lps_play, [
	play_start/3,            % +Source, +Options, -Id
	play_turn/3,             % +Id, +Text, -Result
	play_why/3,              % +Id, +Question, -Lines
	play_status/2,           % +Id, -Dict
	play_stop/1,             % +Id
	play_fork/2,             % +Id, -Id2
	play_diff/3,             % +IdA, +IdB, -Lines
	play_list/1,             % -Games
	play_commands/2,         % +Id, -Commands   what could be done now
	play_parse/3,            % +Id, +Text, -Parse       (for tests)
	play_allowed/2           % +Id, -AllowedSpecs
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pcre), []).
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../core/lps_explain').
:- use_module('../core/lps_diag').
:- use_module(lps_ids).
:- use_module(lps_le).
:- use_module('../syntax/lps_inform').

:- dynamic game/2.               % Id, Dict
:- dynamic game_counter/1.
game_counter(0).

%	How many cycles a burst may take before the turn is cut short. A
%	story whose rules never settle is a bug, and the player should get the
%	prompt back rather than a hung session.
burst_cap(30).

		 /*******************************
		 *	    lifecycle		*
		 *******************************/

%!	play_start(+Source, +Options, -Id) is det.
%
%	Source is `file(Path)` or `text(Source, Name)`. Options: `keys(Dict)`
%	and `model(M)` for the assistant fallback. On a compile failure Id is
%	unbound and an exception `play_failed(Diags)` is thrown.
play_start(Source, Options, Id) :-
	compile_story(Source, Program, Templates),
	lps_session_new(Program, [dc, unbounded], S0),
	%  Cycle 0: the initial state and whatever fires from it, before the
	%  first prompt — Inform's "when play begins".
	settle(S0, S1, Reports0),
	with_mutex(lps_play,
		   ( retract(game_counter(N)), N1 is N + 1,
		     assertz(game_counter(N1)) )),
	format(atom(Base), 'play~w', [N1]),
	tagged_id(Base, Id),
	command_specs(Templates, Allowed),
	( memberchk(keys(Keys), Options) -> true ; Keys = _{} ),
	( memberchk(model(Model), Options) -> true ; Model = null ),
	assertz(game(Id, _{session: S1, program: Program, templates: Templates,
			   allowed: Allowed, turn: 0, transcript: [],
			   keys: Keys, model: Model, last: []})),
	%  The opening: what fired before the first turn, then where you are.
	narrate_reports(Id, Reports0, Lines0),
	look_lines(Id, Look),
	append(Lines0, Look, Opening),
	remember(Id, 0, "", Opening, []).

%	A story is compiled from LE2's terms rather than through the CLI's
%	route because two of its terms are not for playing: the `scenario`
%	(the `Test me with` script the gate replays) and the `maximum time`
%	(which ends a play after a fixed number of cycles). Both are dropped.
compile_story(file(Path), Program, Templates) :-
	( sub_atom(Path, _, _, 0, '.ni') ; sub_atom(Path, _, _, 0, '.inform') ), !,
	lps_inform:inform_to_le(Path, LE, Companion, _),
	story_program(LE, 'story.le', Companion, 'story.lps', Program, Templates).
compile_story(file(Path), Program, Templates) :- !,
	read_file_to_string(Path, Source, [encoding(utf8)]),
	lps_le_companion_name(Path, CPath),
	(   exists_file(CPath)
	->  read_file_to_string(CPath, CSource, [encoding(utf8)])
	;   CSource = ""
	),
	story_program(Source, Path, CSource, CPath, Program, Templates).
compile_story(text(Source, Name), Program, Templates) :-
	story_program(Source, Name, "", none, Program, Templates).
compile_story(text(Source, Name, CSource, CName), Program, Templates) :-
	story_program(Source, Name, CSource, CName, Program, Templates).

story_program(Source, Name, CSource, CName, Program, Templates) :-
	lps_le_translate_text(Source, Name, Text, Prov, LeDiags),
	( diags_ok(LeDiags) -> true ; throw(play_failed(LeDiags)) ),
	lps_le_program_terms(Text, Name, Prov, CSource, CName, Terms0, ReadDiags),
	exclude(script_term, Terms0, Terms),
	lps_compile(terms(Terms), internal, [dc], Program, CDiags),
	append(ReadDiags, CDiags, Diags),
	( diags_ok(Diags) -> true ; throw(play_failed(Diags)) ),
	lps_le_templates(Source, Name, Templates).

script_term(t(observe(_, _), _)).
script_term(t(maxTime(_), _)).

play_stop(Id) :- retractall(game(Id, _)).

%!	play_fork(+Id, -Id2) is det.
%
%	A second game continuing from exactly here. A session is an immutable
%	term (§I.6, M5), so the fork is the same term under a new name; the two
%	games then diverge with what is typed into each, and play_diff/3 says
%	how. This is "what if Alice had not drunk from the bottle".
play_fork(Id, Id2) :-
	game(Id, G),
	with_mutex(lps_play,
		   ( retract(game_counter(N)), N1 is N + 1,
		     assertz(game_counter(N1)) )),
	format(atom(Base), 'play~w', [N1]),
	tagged_id(Base, Id2),
	assertz(game(Id2, G.put(_{parent: Id, forked_at: G.turn}))).

%!	play_diff(+IdA, +IdB, -Lines) is det.
%
%	What happened in one game and not the other, from the cycle they share
%	on: the trace comparison of §I.6, in words.
play_diff(IdA, IdB, Lines) :-
	game(IdA, GA), game(IdB, GB),
	lps_session_trace(GA.session, TA),
	lps_session_trace(GB.session, TB),
	lps_explain:trace_diff(TA, TB, diff(OnlyA, OnlyB)),
	findall(L, diff_line(IdA, GA, OnlyA, L), LA),
	findall(L, diff_line(IdB, GB, OnlyB, L), LB),
	append(LA, LB, Lines0),
	( Lines0 == [] -> Lines = ["The two games have not diverged."] ; Lines = Lines0 ).

diff_line(Id, G, Only, Line) :-
	member(only(events, C, Items), Only),
	include(told_action(G), Items, Told), Told \== [],
	findall(T, ( member(A, Told), ( template_text(G, A, third, T0) -> sentence(T0, T) ; term_to_text(A, T) ) ), Ts),
	atomic_list_concat(Ts, ' ', Text),
	format(string(Line), "only in ~w, cycle ~w: ~w", [Id, C, Text]).

%!	play_list(-Games) is det.
play_list(Games) :-
	findall(_{play: Id, turn: T, parent: P, forked_at: F},
		( game(Id, G), T = G.turn,
		  ( get_dict(parent, G, P) -> true ; P = null ),
		  ( get_dict(forked_at, G, F) -> true ; F = null ) ),
		Games).

play_status(Id, Status) :-
	(   game(Id, G)
	->  lps_session_time(G.session, T),
	    lps_session_status(G.session, St),
	    format(string(StS), "~w", [St]),
	    lps_session_state(G.session, Fluents),
	    maplist(term_to_text, Fluents, State),
	    reverse(G.transcript, Transcript0),
	    maplist(entry_dict, Transcript0, Transcript),
	    Status = _{ok: true, cycle: T, status: StS, turn: G.turn,
		       transcript: Transcript, state: State, allowed: G.allowed}
	;   Status = _{ok: false, error: "no such game"}
	).

%	A transcript entry for the wire: the actions as text, with their cycle.
entry_dict(E, E.put(actions, As)) :-
	findall(_{cycle: T, action: S}, ( member(T-A, E.actions), term_to_text(A, S) ), As).

play_allowed(Id, Allowed) :- game(Id, G), Allowed = G.allowed.

update(Id, Pairs) :- with_mutex(lps_play, update_(Id, Pairs)).
update_(Id, Pairs) :-
	(   game(Id, G)
	->  foldl([K-V, In, Out]>>put_dict(K, In, V, Out), Pairs, G, G1),
	    retractall(game(Id, _)), assertz(game(Id, G1))
	;   true
	).

remember(Id, Turn, Typed, Lines, Actions) :-
	game(Id, G),
	Entry = _{turn: Turn, typed: Typed, lines: Lines, actions: Actions},
	update(Id, [transcript-[Entry|G.transcript], last-Actions]).

term_to_text(T, S) :- format(string(S), "~q", [T]).

		 /*******************************
		 *	     the turn		*
		 *******************************/

%!	play_turn(+Id, +Text, -Result) is det.
%
%	One turn. Result is a dict: `ok`, `turn`, `lines` (the narration),
%	`events` (what was injected, as text), `refused` (what was not), and
%	`cycles` (the first and last cycle of the burst), or `ok: false` with
%	an `error`.
play_turn(Id, Text, Result) :-
	(   game(Id, G)
	->  (   lps_session_status(G.session, running)
	    ->	play_turn_(Id, G, Text, Result)
	    ;	lps_session_status(G.session, St),
		format(string(M), "the story has ended (~w)", [St]),
		Result = _{ok: false, error: M}
	    )
	;   Result = _{ok: false, error: "no such game"}
	).

play_turn_(Id, G, Text, Result) :-
	parse_line(Id, G, Text, Parse),
	(   Parse = events(Events)
	->  Turn is G.turn + 1,
	    S0 = G.session,
	    lps_session_time(S0, T0),
	    lps_session_observe(S0, [begin_turn|Events], S1),
	    settle(S1, S2, Reports1),
	    lps_session_observe(S2, [end_turn], S3),
	    settle(S3, S4, Reports2),
	    append(Reports1, Reports2, Reports),
	    lps_session_time(S4, T4), T1 is T4 - 1,
	    update(Id, [session-S4, turn-Turn]),
	    narrate_reports(Id, Reports, Lines0),
	    ( Lines0 == [] -> Lines = ["Nothing happens."] ; Lines = Lines0 ),
	    report_actions(G, Reports, Actions),
	    remember(Id, Turn, Text, Lines, Actions),
	    maplist(term_to_text, Events, EventsS),
	    Result = _{ok: true, turn: Turn, lines: Lines, events: EventsS,
		       refused: [], cycles: [T0, T1]}
	;   Parse = refused(Term)
	->  format(string(M), "The player's channel does not carry ~q.", [Term]),
	    term_to_text(Term, TermS),
	    Result = _{ok: true, turn: G.turn, lines: [M], events: [],
		       refused: [TermS], cycles: []}
	;   Parse = ambiguous(Words, Cands)
	->  maplist(pretty_name, Cands, Names),
	    atomic_list_concat(Names, ' or ', Or),
	    atomic_list_concat(Words, ' ', W),
	    format(string(M), "Which ~w do you mean: ~w?", [W, Or]),
	    Result = _{ok: true, turn: G.turn, lines: [M], events: [], refused: [], cycles: []}
	;   Parse = unknown_noun(Words)
	->  atomic_list_concat(Words, ' ', W),
	    format(string(M), "You can't see any such thing: ~w.", [W]),
	    Result = _{ok: true, turn: G.turn, lines: [M], events: [], refused: [], cycles: []}
	;   Result = _{ok: true, turn: G.turn, lines: ["I don't understand that."],
		       events: [], refused: [], cycles: []}
	).

%!	settle(+S0, -S, -Reports) is det.
%
%	Step until a cycle in which nothing happened — no event, no action, no
%	composite, no change of state — or the cap. The quiet cycle's report is
%	not kept: it is the sign the burst is over, not part of it.
settle(S0, S, Reports) :-
	burst_cap(Cap),
	settle_(S0, Cap, S, Reports).

settle_(S0, 0, S0, []) :- !.
settle_(S0, N, S, Reports) :-
	(   lps_session_status(S0, running)
	->  lps_session_step(S0, S1, Report),
	    (   quiet(S1, Report)
	    ->	S = S1, Reports = []
	    ;	N1 is N - 1,
		settle_(S1, N1, S, Rest),
		Reports = [Report|Rest]
	    )
	;   S = S0, Reports = []
	).

quiet(S, cycle(T, Events, Composites, _, Actions)) :-
	Events == [], Composites == [], Actions == [],
	\+ state_changed(S, T).
quiet(_, none).

state_changed(S, T) :-
	catch(lps_session_changes(S, T, changes(_, I, Term, U, _)), _, fail),
	( I \== [] ; Term \== [] ; U \== [] ), !.

report_actions(G, Reports, Actions) :-
	findall(T-A, ( member(cycle(T, As, _, _, _), Reports), member(A, As),
		       told_action(G, A) ), Actions).

		 /*******************************
		 *	  what can be done now	*
		 *******************************/

%!	play_commands(+Id, -Commands) is det.
%
%	The commands that would *succeed* from here, as the player would type
%	them: `open the oak door`, `go east`, `og, get the donuts`. Not the
%	grammar — the grammar is every template — but the affordances: each
%	candidate is built from a command template and the things in scope,
%	injected into a copy of the game (a session is a value, so the copy is
%	free), and kept if the burst it starts contains the action and no
%	refusal. That makes the list exactly as contextual as the story's own
%	constraints: a door too small for a big Alice is not offered.
%
%	Commands is a list of dicts: `text` (what to type) and `event` (the
%	term it becomes).
play_commands(Id, Commands) :-
	game(Id, G),
	(   lps_session_status(G.session, running)
	->  candidates(G, Cands0),
	    list_to_set(Cands0, Cands1),
	    %  A bound, so a story with a hundred things in one room does not
	    %  make the button a minute long.
	    ( length(Cands1, N), N > 300 -> length(Cands, 300), append(Cands, _, Cands1) ; Cands = Cands1 ),
	    findall(_{text: Text, event: ES},
		    ( member(Ev, Cands), possible(G, Ev),
		      command_text(G, Ev, Text), term_to_text(Ev, ES) ),
		    Commands)
	;   Commands = []
	).

%	Every command template, with each slot filled from what is in scope.
candidates(G, Cands) :-
	findall(Ev, candidate(G, Ev), Cands).

candidate(G, Ev) :-
	member(T, G.templates), T = le_template(F/A, event, _, Slots, _, _),
	command_pattern(T, Kind, F/A, Pattern),
	(   Kind == player
	->  length(Args, A), fill_slots(G, Pattern, Slots, 0, Args),
	    carried_where_needed(G, Pattern, Args),
	    Ev =.. [F|Args]
	;   %  an order: the actor is a person here who is not the player
	    persons_here(G, Ps), member(Who, Ps),
	    A1 is A - 1, length(Rest, A1),
	    fill_slots(G, Pattern, Slots, 1, Rest),
	    Ev =.. [F, Who|Rest]
	).

%	Two-slot commands multiply: five things make twenty-five `put X into Y`
%	and as many `lock X with Y`. What is put must be carried and so must
%	the key, and that is known from the state without a probe; the rest of
%	the pruning is the probe's job.
carried_where_needed(G, Pattern, Args) :-
	lps_session_state(G.session, Fluents),
	forall(( append(_, [into, slot(K)|_], Pattern) ; append(_, [onto, slot(K)|_], Pattern) ),
	       ( nth0(0, Args, X), memberchk(carries(player, X), Fluents), K = K )),
	forall(append(_, [with, slot(K2)|_], Pattern),
	       ( nth0(K2, Args, Key), memberchk(carries(player, Key), Fluents) )).

fill_slots(_, _, _, _, []).
fill_slots(G, Pattern, Slots, K, [V|Vs]) :-
	memberchk(slot(K, Type0), Slots),
	%  `second person` is a person: the head noun is the last word.
	( atomic_list_concat(Ws, ' ', Type0), last(Ws, Type) -> true ; Type = Type0 ),
	slot_value(G, Type, V),
	K1 is K + 1,
	fill_slots(G, Pattern, Slots, K1, Vs).

slot_value(G, direction, D) :- !,
	lps_session_state(G.session, Fluents),
	( player_room(Fluents, Room) -> exits(G, Fluents, Room, Ds) ; Ds = [] ),
	member(D, Ds).
slot_value(G, person, P) :- !, ( P = player ; persons_here(G, Ps), member(P, Ps) ).
slot_value(G, _, X) :- things_in_scope(G, Xs), member(X, Xs).

persons_here(G, Ps) :-
	lps_session_state(G.session, Fluents),
	(   player_room(Fluents, Room)
	->  findall(P, ( member(in(P, Room), Fluents), P \== player, is_person(G, P) ), Ps0),
	    sort(Ps0, Ps)
	;   Ps = []
	).

%	What the player could name: in the room, on or in something open
%	there, carried, or carried by someone in the room (an order can be
%	about that: "ogg, give the donuts to me").
things_in_scope(G, Xs) :-
	lps_session_state(G.session, Fluents),
	findall(X, ( player_room(Fluents, Room), visible_in(Fluents, Room, X, 4) ), Xs1),
	findall(X, member(carries(player, X), Fluents), Xs2),
	findall(X, ( persons_here(G, Ps), member(P, Ps), member(carries(P, X), Fluents) ), Xs3),
	append([Xs1, Xs2, Xs3], Xs0), sort(Xs0, Xs).

%	Would it work? Inject it into a copy of the game and look at the burst.
possible(G, Ev) :-
	catch(( lps_session_observe(G.session, [begin_turn, Ev], S1),
		settle(S1, _, Reports) ), _, fail),
	findall(A, ( member(cycle(_, Happened, _, _, _), Reports), member(A, Happened),
		     p_action(G.program, A) ), Actions),
	Actions \== [],
	\+ ( member(A, Actions), A =.. [F|_], atom_concat(refuse_, _, F) ).

%	"put the banana into the box", "go north", "og, get the donuts".
command_text(G, Ev, Text) :-
	Ev =.. [F|Args], length(Args, A),
	member(T, G.templates), T = le_template(F/A, event, _, _, _, _),
	command_pattern_raw(T, Kind, F/A, Pattern), !,
	(   Kind == player
	->  fill_command(G, Pattern, Args, Pieces), atomic_list_concat(Pieces, ' ', Text0),
	    normalize_space(string(Text), Text0)
	;   Args = [Who|_], pretty_name(Who, WN),
	    fill_command(G, Pattern, Args, Pieces), atomic_list_concat(Pieces, ' ', Text0),
	    normalize_space(string(T1), Text0),
	    format(string(Text), "~w, ~w", [WN, T1])
	).

fill_command(_, [], _, []).
fill_command(G, [slot(K)|Ps], Args, [P|Rest]) :- !,
	nth0(K, Args, V),
	( V == player -> P = me ; direction_word(V, _) -> P = V ; noun_phrase(G, the, V, P) ),
	fill_command(G, Ps, Args, Rest).
fill_command(G, [W|Ps], Args, [W|Rest]) :-
	fill_command(G, Ps, Args, Rest).

		 /*******************************
		 *	     the parser		*
		 *******************************/

%!	play_parse(+Id, +Text, -Parse) is det.
%
%	Parse is one of `events(List)`, `refused(Term)`, `ambiguous(Words,
%	Candidates)`, `unknown_noun(Words)` or `none`.
play_parse(Id, Text, Parse) :-
	game(Id, G),
	parse_line(Id, G, Text, Parse).

parse_line(_, G, Text, Parse) :-
	string_concat("!", Raw, Text), !,
	%  A raw event term, for the person who knows the vocabulary — on the
	%  same channel, with the same allow-list. This is the gate's test that
	%  the channel refuses a fluent.
	parse_event(Raw, Term),
	(   Term == none
	->  Parse = none
	;   allowed_term(G, Term)
	->  Parse = events([Term])
	;   Parse = refused(Term)
	).
parse_line(Id, G, Text, Parse) :-
	words_of(Text, Words0),
	(   Words0 == []
	->  Parse = none
	;   normalise(Words0, Words),
	    (   Words = [Actor, ',' | Rest], Rest \== []
	    ->	resolve_actor(G, Actor, Who),
		Patterns = G.templates,
		match_command(G, ask(Who), Rest, Patterns, Parse0)
	    ;	match_command(G, player, Words, G.templates, Parse0)
	    ),
	    (   Parse0 = events(_)
	    ->	Parse = Parse0
	    ;	Parse0 \== none
	    ->	Parse = Parse0
	    ;	llm_parse(Id, G, Text, Parse)
	    )
	).

%	Words, lower-cased, punctuation separated; a comma is kept because
%	"og, get donuts" is an order.
words_of(Text, Words) :-
	string_lower(Text, Lower),
	re_split("[\\s]+|(,)", Lower, Parts),
	findall(W, ( member(P, Parts), normalize_space(atom(W0), P), W0 \== '',
		     ( W0 == ',' -> W = ',' ; atom_strip_punct(W0, W) ), W \== '' ),
		Words).

atom_strip_punct(A0, A) :-
	atom_codes(A0, Cs0),
	exclude([C]>>memberchk(C, `.!?;:"'`), Cs0, Cs),
	atom_codes(A, Cs).

%	Inform's `Understand` lines, the dozen every parser IF player types.
normalise(Ws0, Ws) :-
	exclude(article, Ws0, Ws1),
	( synonym(Ws1, Ws2) -> true ; Ws2 = Ws1 ),
	maplist(word_synonym, Ws2, Ws).

article(the). article(a). article(an). article(some).

synonym([get, all], [take, all]) :- !.
synonym([i], [take, inventory]) :- !.
synonym([inv], [take, inventory]) :- !.
synonym([inventory], [take, inventory]) :- !.
synonym([l], [look]) :- !.
synonym([z], [wait]) :- !.
synonym([out], [exit]) :- !.
synonym([leave], [exit]) :- !.
synonym([get, out], [exit]) :- !.
synonym([get, out|_], [exit]) :- !.
synonym([climb, out|_], [exit]) :- !.
synonym([get, in|Rest], [enter|Rest]) :- !.
synonym([get, into|Rest], [enter|Rest]) :- !.
synonym([climb, into|Rest], [enter|Rest]) :- !.
synonym([climb, in|Rest], [enter|Rest]) :- !.
synonym([go, into|Rest], [enter|Rest]) :- !.
synonym([go, in|Rest], [enter|Rest]) :- !.
synonym([look, at|Rest], [examine|Rest]) :- !.
synonym([pick, up|Rest], [take|Rest]) :- !.
synonym([put, down|Rest], [drop|Rest]) :- !.
synonym([D], [go, Dir]) :- direction_word(D, Dir), !.
synonym([go, D], [go, Dir]) :- direction_word(D, Dir), !.
synonym([put, X, in, Y], [put, X, into, Y]) :- !.
synonym([put, X, on, Y], [put, X, onto, Y]) :- !.
synonym([put, X1, X2, in, Y], [put, X1, X2, into, Y]) :- !.
synonym([put, X1, X2, on, Y], [put, X1, X2, onto, Y]) :- !.
synonym([put, X, in, Y1, Y2], [put, X, into, Y1, Y2]) :- !.
synonym([put, X, on, Y1, Y2], [put, X, onto, Y1, Y2]) :- !.
synonym([give, me|Rest], [give|Rest]) :- append(Rest, [to, me], _), !, fail.

word_synonym(get, take) :- !.
word_synonym(grab, take) :- !.
word_synonym(x, examine) :- !.
word_synonym(inspect, examine) :- !.
word_synonym(me, player) :- !.
word_synonym(W, W).

direction_word(n, north). direction_word(s, south). direction_word(e, east).
direction_word(w, west). direction_word(u, up). direction_word(d, down).
direction_word(ne, northeast). direction_word(nw, northwest).
direction_word(se, southeast). direction_word(sw, southwest).
direction_word(north, north). direction_word(south, south).
direction_word(east, east). direction_word(west, west).
direction_word(up, up). direction_word(down, down).
direction_word(northeast, northeast). direction_word(northwest, northwest).
direction_word(southeast, southeast). direction_word(southwest, southwest).

%	The actor of "og, get donuts": a person of the story, by name.
resolve_actor(G, Word, Who) :-
	(   resolve_noun(G, [Word], _, one(Who)) -> true ; Who = Word ).

/*  A command pattern is a command template's surface with its `*a thing*`
    slots as holes: `the command is to put *a thing* into *a container*` is
    [put, slot(0), into, slot(1)], and the event is cmd_insert(Thing,
    Container) with the slots in argument order — which is how the LE
    surface language defines argument order (docs/le_lps_surface.md §2).

    An order to a character is a template `*a person* is asked to … *a
    thing*`: its first slot is the actor and the rest is the pattern. */
command_pattern(T, Kind, FA, Pattern) :-
	command_pattern_raw(T, Kind, FA, Raw),
	%  Through the same synonym table as the input, so a template that
	%  says `get` and a player who types `take` meet in the middle. The
	%  raw pattern is what the words shown to the player come from.
	maplist([W0, W]>>( atom(W0) -> word_synonym(W0, W) ; W = W0 ), Raw, Pattern).

command_pattern_raw(le_template(F/A, event, Surface, _, _, _), player, F/A, Pattern) :-
	string_concat("the command is to ", Rest, Surface),
	surface_pattern(Rest, 0, Pattern).
command_pattern_raw(le_template(F/A, event, Surface, _, _, _), ask, F/A, Pattern) :-
	re_matchsub("^\\*[^*]*\\* is asked to (.*)$", Surface, Sub, []),
	get_dict(1, Sub, Rest),
	surface_pattern(Rest, 1, Pattern).

surface_pattern(Text, K0, Pattern) :-
	re_split("(\\*[^*]*\\*)", Text, Parts),
	parts_pattern(Parts, K0, Pattern).

parts_pattern([], _, []).
parts_pattern([P|Ps], K, Pattern) :-
	(   sub_string(P, 0, 1, _, "*")
	->  Pattern = [slot(K)|Rest], K1 is K + 1
	;   split_string(P, " ", " ", Ws0),
	    exclude(==(""), Ws0, Ws),
	    maplist([S, W]>>atom_string(W, S), Ws, Words),
	    append(Words, Rest, Pattern), K1 = K
	),
	parts_pattern(Ps, K1, Rest).

%	The list the channel may carry, as `name/arity` strings, for the status
%	and for the assistant's prompt.
command_specs(Templates, Specs) :-
	findall(Spec, ( member(T, Templates), command_pattern(T, _, F/A, _),
			format(atom(Spec), '~w/~w', [F, A]) ), Specs0),
	sort(Specs0, Specs).

allowed_term(G, Term) :-
	functor(Term, F, A),
	format(atom(Spec), '~w/~w', [F, A]),
	memberchk(Spec, G.allowed).

%!	match_command(+G, +Actor, +Words, +Templates, -Parse) is det.
%
%	The first template whose pattern takes all the words wins; a pattern
%	whose slot cannot be resolved reports why, so "open box" among three
%	boxes asks which. `take all` is every takeable thing in the room.
match_command(G, player, [take, all], _, Parse) :- !,
	(   things_here(G, Things), Things \== []
	->  findall(cmd_take(X), member(X, Things), Es), Parse = events(Es)
	;   Parse = unknown_noun([all])
	).
match_command(G, Actor, Words, Templates, Parse) :-
	actor_kind(Actor, Kind),
	%  The wordiest pattern first: `take inventory` before `take <thing>`,
	%  or "inventory" is looked up as a thing.
	findall(N-p(F/A, Pattern),
		( member(T, Templates), command_pattern(T, Kind, F/A, Pattern),
		  include(atom, Pattern, Fixed), length(Fixed, N) ),
		Ps0),
	sort(0, @>=, Ps0, Ps),
	(   member(_-p(F/A, Pattern), Ps),
	    match_pattern(G, Pattern, Words, Bindings, Outcome),
	    Outcome \== none
	->  (   Outcome == ok
	    ->	actor_slot(Actor, Bindings, Bindings1),
		length(Args, A), msort(Bindings1, Sorted),
		findall(V, member(_-V, Sorted), Args),
		Event =.. [F|Args],
		Parse = events([Event])
	    ;	Parse = Outcome
	    )
	;   Parse = none
	).

actor_kind(player, player).
actor_kind(ask(_), ask).

actor_slot(player, B, B).
actor_slot(ask(Who), B, [0-Who|B]).

%	Outcome: ok | ambiguous(Words, Cands) | unknown_noun(Words) | none
match_pattern(G, Pattern, Words, Bindings, Outcome) :-
	(   match_pat(G, Pattern, Words, [], Bindings, Outcome0)
	->  Outcome = Outcome0
	;   Outcome = none, Bindings = []
	).

match_pat(_, [], [], B, B, ok).
match_pat(G, [W|Ps], [W|Ws], B0, B, O) :-
	atom(W),
	match_pat(G, Ps, Ws, B0, B, O).
match_pat(G, [slot(K)|Ps], Ws, B0, B, O) :-
	next_fixed(Ps, Fixed),
	take_phrase(Ws, Fixed, Phrase, Rest),
	Phrase \== [],
	(   resolve_noun(G, Phrase, K, R)
	->  (   R = one(V)
	    ->	match_pat(G, Ps, Rest, [K-V|B0], B, O)
	    ;	R = many(Cands)
	    ->	B = B0, O = ambiguous(Phrase, Cands)
	    )
	;   B = B0, O = unknown_noun(Phrase)
	).

next_fixed([W|_], W) :- atom(W), !.
next_fixed(_, none).

%	The words up to the next fixed word of the pattern (or all of them).
take_phrase(Ws, none, Ws, []) :- !.
take_phrase(Ws, Fixed, Phrase, Rest) :-
	append(Phrase, [Fixed|Rest0], Ws), !,
	Rest = [Fixed|Rest0].

%!	resolve_noun(+G, +Words, +Slot, -Result) is semidet.
%
%	A noun phrase to a constant of the program. Directions are
%	directions; `player` is the player; anything else is looked up among
%	the constants the state and the timeless facts mention, by the words
%	of its name (`oak_door` is "oak door", and "door" finds it). Several
%	matches prefer what is in scope; if that does not settle it, the
%	player is asked.
resolve_noun(_, [W], _, one(D)) :- direction_word(W, D), !.
resolve_noun(_, [player], _, one(player)) :- !.
resolve_noun(G, Words, _, Result) :-
	constants(G, Cs),
	findall(C, ( member(C, Cs), name_matches(C, Words) ), Cands0),
	(   Cands0 == []
	->  %  "og" for Ogg: a prefix of a name's word, as a last resort.
	    findall(C, ( member(C, Cs), prefix_matches(C, Words) ), Cands1)
	;   Cands1 = Cands0
	),
	sort(Cands1, Cands),
	Cands \== [],
	(   Cands = [C]
	->  Result = one(C)
	;   findall(C, ( member(C, Cands), exact_name(C, Words) ), Exact),
	    Exact = [C]
	->  Result = one(C)
	;   findall(C, ( member(C, Cands), in_scope(G, C) ), Here),
	    Here = [C]
	->  Result = one(C)
	;   Result = many(Cands)
	).

name_matches(C, Words) :-
	atom(C), name_words(C, NWs),
	subsequence(Words, NWs).

exact_name(C, Words) :- name_words(C, Words).

prefix_matches(C, Words) :-
	atom(C), name_words(C, NWs),
	forall(member(W, Words),
	       ( atom_length(W, L), L >= 2,
		 member(N, NWs), sub_atom(N, 0, _, _, W) )).

name_words(C, Ws) :- atomic_list_concat(Ws, '_', C).

subsequence([], _).
subsequence([W|Ws], [W|Ns]) :- !, subsequence(Ws, Ns).
subsequence(Ws, [_|Ns]) :- subsequence(Ws, Ns).

%	Every atom the state or a timeless fact mentions as an argument.
constants(G, Cs) :-
	lps_session_state(G.session, Fluents),
	findall(A, ( member(F, Fluents), arg_atom(F, A) ), As1),
	prog_module(G.program, M),
	findall(A, ( member(le_template(P/N, predicate, _, _, _, _), G.templates), N > 0,
		     functor(H, P, N), catch(clause(M:H, true), _, fail),
		     arg_atom(H, A) ),
		As2),
	append(As1, As2, As),
	sort(As, Cs0),
	exclude(reserved_constant, Cs0, Cs).

reserved_constant(true). reserved_constant(false).

arg_atom(T, A) :- compound(T), arg(_, T, X), ( atom(X) -> A = X ; arg_atom(X, A) ).

%	What the player can get at, for disambiguation and for `take all`.
in_scope(G, X) :-
	lps_session_state(G.session, Fluents),
	player_room(Fluents, Room),
	visible_in(Fluents, Room, X, 4), !.
in_scope(G, X) :-
	lps_session_state(G.session, Fluents),
	memberchk(carries(player, X), Fluents).

player_room(Fluents, Room) :-
	memberchk(in(player, H), Fluents),
	( memberchk(in(H, R), Fluents) -> Room = R ; Room = H ).

visible_in(Fluents, H, X, _) :- member(in(X, H), Fluents), X \== player.
visible_in(Fluents, H, X, _) :- member(on(X, H), Fluents).
visible_in(Fluents, H, X, D) :-
	D > 0, D1 is D - 1,
	( member(in(C, H), Fluents) ; member(on(C, H), Fluents) ),
	C \== player,
	\+ memberchk(closed(C), Fluents),
	visible_in(Fluents, C, X, D1).

things_here(G, Things) :-
	lps_session_state(G.session, Fluents),
	player_room(Fluents, Room),
	findall(X, ( member(in(X, Room), Fluents), X \== player,
		     \+ is_person(G, X), \+ fixed(G, X) ), Things).

is_person(G, X) :- catch(p_call(G.program, is_a_person(X)), _, fail), !.
fixed(G, X) :- catch(p_call(G.program, is_fixed_in_place(X)), _, fail), !.

%	The assistant's translator, offered the same events and nothing else;
%	only if a key is there to use. What comes back is checked against the
%	channel exactly as a typed term is.
llm_parse(_, G, Text, Parse) :-
	(   catch(lps_assistant:assistant_translate(G.program, Text,
						     [keys(G.keys), model(G.model),
						      allowed(G.allowed)], Strings), _, fail),
	    Strings \== []
	->  maplist(parse_event, Strings, Terms0),
	    exclude(==(none), Terms0, Terms),
	    (   Terms = [T|_], \+ allowed_term(G, T)
	    ->	Parse = refused(T)
	    ;	Terms \== []
	    ->	Parse = events(Terms)
	    ;	Parse = none
	    )
	;   Parse = none
	).

parse_event(S, Event) :-
	current_prolog_flag(allow_dot_in_atom, Old),
	setup_call_cleanup(
	    set_prolog_flag(allow_dot_in_atom, true),
	    catch(term_string(Event, S), _, Event = none),
	    set_prolog_flag(allow_dot_in_atom, Old)).

		 /*******************************
		 *	    the narrator	*
		 *******************************/

%!	narrate_reports(+Id, +Reports, -Lines) is det.
%	A report's `Events` field is what happened by that cycle — the
%	observed events and the actions committed in the cycle before; its
%	last field is what is committed to happen next. The story is the
%	first.
narrate_reports(Id, Reports, Lines) :-
	game(Id, G),
	findall(L, ( member(cycle(T, Happened, _, _, _), Reports),
		     member(A, Happened),
		     told_action(G, A),
		     narrate_action(Id, G, A, T, L) ),
		Lines).

%	The report's last field carries everything that happened in the
%	cycle — the observed events and the composites too. What is told is
%	the declared actions, and the system actions a `narrate/2` may mention.
told_action(G, A) :- p_action(G.program, A), !.
told_action(_, A) :- system_action(A).

%	One action, one line — or none, for the system actions that change
%	state and for what the story says not to tell.
narrate_action(Id, G, A, _, Line) :-
	catch(p_call(G.program, narrate(A, Text)), _, fail), !,
	Text \== none,
	%  A story's words for going somewhere come before the place itself.
	(   A = go(player, _)
	->  look_lines(Id, Ls), atomic_list_concat([Text|Ls], '\n', Line)
	;   format(string(Line), "~w", [Text])
	).
narrate_action(_, _, A, _, _) :- system_action(A), !, fail.
narrate_action(Id, G, A, T, Line) :-
	A =.. [F|Args],
	(   atom_concat(refuse_, F1, F)
	->  Action =.. [F1|Args],
	    refusal_line(G, Action, T, Line)
	;   report_action(Id, G, A, Line)
	->  true
	;   action_line(G, A, Line)
	).

system_action(initiate(_)). system_action(terminate(_)). system_action(update(_, _, _)).
system_action(lps_terminate).

%	`look`, `examine`, `inventory`, `wait`, and a `go` that arrived
%	somewhere: told from the state, not from the template.
report_action(Id, _, look(player), Line) :- !,
	look_lines(Id, Ls), atomic_list_concat(Ls, '\n', Line).
report_action(Id, G, go(player, _), Line) :- !,
	look_lines(Id, Ls), atomic_list_concat(Ls, '\n', Line0),
	( G == G -> Line = Line0 ; true ).
report_action(_, _, wait(player), "Time passes.") :- !.
report_action(_, G, inventory(player), Line) :- !,
	lps_session_state(G.session, Fluents),
	findall(N, ( member(carries(player, X), Fluents), noun_phrase(G, a, X, N) ), Ns),
	(   Ns == []
	->  Line = "You are carrying nothing."
	;   list_text(Ns, L), format(string(Line), "You are carrying ~w.", [L])
	).
report_action(_, G, examine(player, X), Line) :- !,
	lps_session_state(G.session, Fluents),
	noun_phrase(G, the, X, NX),
	format(string(L0), "You see nothing special about ~w.", [NX]),
	findall(N, ( ( member(in(Y, X), Fluents) ; member(on(Y, X), Fluents) ),
		     Y \== player, noun_phrase(G, a, Y, N) ), Ns),
	(   memberchk(closed(X), Fluents)
	->  ( memberchk(locked(X), Fluents) -> L1 = " It is closed and locked." ; L1 = " It is closed." )
	;   Ns \== []
	->  list_text(Ns, L), format(string(L1), " In it: ~w.", [L])
	;   L1 = ""
	),
	string_concat(L0, L1, Line).

%!	look_lines(+Id, -Lines) is det.
%
%	Where the player is, what is there, and which ways lead out.
look_lines(Id, Lines) :-
	game(Id, G),
	lps_session_state(G.session, Fluents),
	(   memberchk(in(player, H), Fluents)
	->  (   memberchk(in(H, Room), Fluents)
	    ->	noun_phrase(G, the, H, NH), format(string(Inside), " (in ~w)", [NH])
	    ;	Room = H, Inside = ""
	    ),
	    pretty_title(Room, Title),
	    format(string(L1), "~w~w", [Title, Inside]),
	    %  A story's companion may say what a room looks like.
	    (   catch(p_call(G.program, description(Room, Desc)), _, fail)
	    ->	format(string(LD), "~w", [Desc]), Ls0 = [LD]
	    ;	Ls0 = []
	    ),
	    findall(N, ( member(in(X, Room), Fluents), X \== player, X \== H,
			 \+ is_person(G, X), noun_phrase(G, a, X, N) ), Things),
	    findall(N, ( member(in(X, Room), Fluents), X \== player,
			 is_person(G, X), pretty_title(X, N) ), People),
	    (   Things == [] -> Ls1 = []
	    ;	list_text(Things, LT), format(string(L2), "You can see ~w here.", [LT]), Ls1 = [L2]
	    ),
	    (   People == [] -> Ls2 = []
	    ;	list_text(People, LP), format(string(L3), "~w is here.", [LP]), Ls2 = [L3]
	    ),
	    (   exits(G, Fluents, Room, Ds), Ds \== []
	    ->	atomic_list_concat(Ds, ', ', DT), format(string(L4), "Exits: ~w.", [DT]), Ls3 = [L4]
	    ;	Ls3 = []
	    ),
	    append([[L1], Ls0, Ls1, Ls2, Ls3], Lines)
	;   Lines = ["You are nowhere in particular."]
	).

%	The exits, through the program's own intensional fluent `leads`,
%	evaluated against the current state the way a scene is. A story that
%	does not use the library's map has none, which is an empty list.
exits(G, Fluents, Room, Ds) :-
	lps_session_time(G.session, T),
	%  The store is per thread, and an HTTP worker that has not stepped
	%  this session has no program installed: the query would find no
	%  `leads` clauses and offer no way out. Install it, as a scene does.
	catch(( G.session = session(_, P, Opts, _, _, Store, _, _, _),
		lps_session:install(P, Opts), lps_store:store_load(Store) ), _, true),
	catch(lps_explain:with_borrowed_state(Fluents, T,
		  findall(D, lps_query:dc_query(holds(leads(D, Room, _), T)), Ds0)),
	      _, Ds0 = []),
	sort(Ds0, Ds).

%!	refusal_line(+G, +Action, +T, -Line) is det.
%
%	"You can't <do that>: <the condition that forbade it>." — the
%	explanation layer as the message. The denial that blocked the action is
%	in the trace; its conditions other than the action itself are the
%	reason, and each is told through its template.
refusal_line(G, Action, T, Line) :-
	action_phrase(G, Action, infinitive, Phrase),
	lps_session_trace(G.session, Trace),
	Cycle is T - 1,
	(   member(action_blocked(Cycle, E, _, _, Denial), Trace), \+ E \= Action
	->  %  A denial reads `false action, context…, the decisive condition`;
	    %  the last condition is the one worth saying. A variable it leaves
	    %  unbound is "anything".
	    exclude([C]>>(C = happens(_, _, _)), Denial, Conds),
	    (   last(Conds, Last)
	    ->	anything_for_variables(Last, Last1),
		condition_text(G, Last1, RT), format(string(Reason), ": ~w", [RT])
	    ;	Reason = ""
	    ),
	    format(string(Line), "You can't ~w~w.", [Phrase, Reason])
	;   format(string(Line), "You can't ~w.", [Phrase])
	).

%	The trace keeps a denial with its variables named ('$VAR'(N)), so a
%	slot the constraint left open reads as "anything" rather than as A.
anything_for_variables(T, anything) :- var(T), !.
anything_for_variables('$VAR'(_), anything) :- !.
anything_for_variables(T, T) :- atomic(T), !.
anything_for_variables(T0, T) :-
	T0 =.. [F|As0], maplist(anything_for_variables, As0, As), T =.. [F|As].

condition_text(G, holds(not(F), _), Text) :- !,
	fluent_text(G, F, Pos), negate_text(Pos, Text).
condition_text(G, holds(F, _), Text) :- !, fluent_text(G, F, Text).
condition_text(G, not(F), Text) :- !, condition_text(G, F, Pos), negate_text(Pos, Text).
condition_text(G, \+ F, Text) :- !, condition_text(G, F, Pos), negate_text(Pos, Text).
condition_text(_, A \== B, Text) :- !, format(string(Text), "~w is not ~w", [A, B]).
condition_text(G, F, Text) :- fluent_text(G, F, Text).

fluent_text(G, F, Text) :-
	(   template_text(G, F, third, Text0)
	->  Text = Text0
	;   format(string(Text), "~q", [F])
	).

negate_text(Pos, Neg) :-
	(   string_concat("you ", Rest, Pos), \+ sub_string(Rest, 0, _, _, "are "),
	    \+ sub_string(Rest, 0, _, _, "can ")
	->  string_concat("you do not ", Rest, Neg)
	;   sub_string(Pos, B, _, A, " can ")
	->  sub_string(Pos, 0, B, _, L), sub_string(Pos, _, A, 0, R),
	    atomic_list_concat([L, " cannot ", R], Neg)
	;   sub_string(Pos, B, _, A, " is ")
	->  sub_string(Pos, 0, B, _, L), sub_string(Pos, _, A, 0, R),
	    atomic_list_concat([L, " is not ", R], Neg)
	;   sub_string(Pos, B, _, A, " are ")
	->  sub_string(Pos, 0, B, _, L), sub_string(Pos, _, A, 0, R),
	    atomic_list_concat([L, " are not ", R], Neg)
	;   format(string(Neg), "it is not the case that ~w", [Pos])
	).

%	A plain action, through its template: "You take the lamp." / "Ogg
%	unlocks the case with the silver key."
action_line(G, A, Line) :-
	(   template_text(G, A, third, Text)
	->  sentence(Text, Line)
	;   format(string(Line), "~q.", [A])
	).

%	The phrase after "You can't": "open the case".
action_phrase(G, A, infinitive, Phrase) :-
	A =.. [_|Args],
	(   Args = [player|_], template_text(G, A, infinitive, Text)
	->  Phrase = Text
	;   template_text(G, A, third, Text)
	->  Phrase = Text
	;   format(string(Phrase), "~q", [A])
	).

%!	template_text(+G, +Term, +Mood, -Text) is semidet.
%
%	The template's surface with the slots filled. Mood `third` keeps the
%	surface's verb, except that a first slot that is the player becomes
%	"you" with the verb de-conjugated ("You take …"); `infinitive` drops a
%	leading player slot and de-conjugates ("take the lamp").
template_text(G, Term, Mood, Text) :-
	Term =.. [F|Args], length(Args, A),
	member(le_template(F/A, _, Surface, _, _, _), G.templates),
	surface_pattern(Surface, 0, Pattern),
	fill_pattern(G, Pattern, Args, Mood, Pieces),
	atomic_list_concat(Pieces, ' ', Text0),
	normalize_space(string(Text), Text0).

fill_pattern(G, [slot(0)|Rest], Args, Mood, Pieces) :-
	Args = [player|_], !,
	fill_rest(G, Rest, Args, second, Rest1),
	( Mood == infinitive -> Pieces = Rest1 ; Pieces = ['you'|Rest1] ).
fill_pattern(G, Pattern, Args, _, Pieces) :-
	fill_rest(G, Pattern, Args, third, Pieces).

%	After a "you" the next word is the verb, and it loses its -s.
fill_rest(_, [], _, _, []).
fill_rest(G, [slot(K)|Ps], Args, Person, [P|Rest]) :- !,
	nth0(K, Args, V),
	( V == player -> P = you ; noun_phrase(G, the, V, P) ),
	fill_rest(G, Ps, Args, Person, Rest).
fill_rest(G, [W|Ps], Args, second, [V|Rest]) :- !,
	second_person(W, V),
	fill_rest(G, Ps, Args, third, Rest).
fill_rest(G, [W|Ps], Args, third, [W|Rest]) :-
	fill_rest(G, Ps, Args, third, Rest).

second_person(is, are) :- !.
second_person(has, have) :- !.
second_person(does, do) :- !.
second_person(goes, go) :- !.
second_person(carries, carry) :- !.
second_person(tries, try) :- !.
second_person(W, V) :-
	atom_concat(Stem, ies, W), !, atom_concat(Stem, y, V).
second_person(W, V) :-
	member(Suffix, [ses, xes, zes, ches, shes, oes]),
	atom_concat(Stem, Suffix, W), !,
	sub_atom(Suffix, 0, _, 2, Root), atom_concat(Stem, Root, V).
second_person(W, V) :-
	atom_concat(V, s, W), \+ atom_concat(_, ss, W), !.
second_person(W, W).

%	"the oak door", "an apple", "Ogg", "east", "anything".
noun_phrase(G, Det, X, P) :-
	(   atom(X), is_person(G, X) -> pretty_title(X, P)
	;   noun_phrase(Det, X, P)
	).

noun_phrase(Det, X, P) :-
	(   atom(X), \+ direction_word(X, _), X \== player, X \== anything
	->  pretty_name(X, N), article(Det, N, D), format(atom(P), '~w ~w', [D, N])
	;   pretty_name(X, P)
	).

article(a, N, an) :- sub_atom(N, 0, 1, _, F), memberchk(F, [a, e, i, o, u]), !.
article(D, _, D).

pretty_name(X, N) :-
	(   atom(X) -> atomic_list_concat(Ws, '_', X), atomic_list_concat(Ws, ' ', N)
	;   format(atom(N), '~w', [X])
	).

pretty_title(X, T) :-
	pretty_name(X, N), atom_string(N, S),
	( sub_string(S, 0, 1, _, F0), string_upper(F0, F), sub_string(S, 1, _, 0, R) -> string_concat(F, R, T) ; T = S ).

sentence(Text, Line) :-
	atom_string(Text, S),
	sub_string(S, 0, 1, _, F0), string_upper(F0, F), sub_string(S, 1, _, 0, R),
	format(string(Line), "~w~w.", [F, R]).

list_text([X], X) :- !.
list_text([X, Y], T) :- !, format(string(T), "~w and ~w", [X, Y]).
list_text([X|Xs], T) :- list_text(Xs, R), format(string(T), "~w, ~w", [X, R]).

		 /*******************************
		 *	      why		*
		 *******************************/

%!	play_why(+Id, +Question, -Lines) is det.
%
%	Question is a term for lps_session_explain/3, or `last` for "why did
%	the last turn go the way it did" — one explanation per action of the
%	turn, the refusals asked as `why_not` of the action they refused.
play_why(Id, last, Lines) :- !,
	game(Id, G),
	findall(L, ( member(T-A, G.last), why_lines(G, T, A, Ls), member(L, Ls) ), Lines).
play_why(Id, Question, Lines) :-
	game(Id, G),
	lps_session_explain(G.session, Question, E),
	explanation_text(E, Lines).

why_lines(G, T, A, Lines) :-
	A =.. [F|Args],
	(   atom_concat(refuse_, F1, F)
	->  Action =.. [F1|Args], Q = why_not(happened(Action), T)
	;   Q = why(happened(A), T)
	),
	lps_session_explain(G.session, Q, E),
	explanation_text(E, Ls),
	format(atom(H), '~q:', [Q]),
	Lines = [H|Ls].
