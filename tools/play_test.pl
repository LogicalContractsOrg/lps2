/* play_test.pl — the phase-2 gate of docs/project/plans/InformPlan.md.
 *
 * A story is playable from typed English with no LLM key: the parser is the
 * story's own command templates, a refusal is narrated from the engine's
 * explanation, a character acts on an order, `why` answers on a transcript
 * line, and the player's channel refuses a fluent.
 *
 *   LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/play_test.pl')" -g "play_test:main" -t halt
 */

:- module(play_test, [main/0]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../src/lps').
:- use_module('../src/edges/lps_cli').
:- use_module('../src/edges/lps_play').

said_all(_, []).
said_all(R, [P|Ps]) :- said(R, P), said_all(R, Ps).

main :-
	format('~n=== Phase 2: playing the stories ===~n~n', []),
	(   getenv('LPS_LE2_LIB', _)
	->  true
	;   format('LPS_LE2_LIB is not set: the stories are Logical English.~n', []), halt(1)
	),
	findall(R, ( test(Name, Goal), run_test(Name, Goal, R) ), Rs),
	include(==(ok), Rs, Oks),
	length(Rs, N), length(Oks, NOk),
	format('~n=== ~w/~w play checks pass ===~n', [NOk, N]),
	( NOk =:= N -> true ; halt(1) ).

run_test(Name, Goal, R) :-
	(   catch(Goal, E, ( format('  ~w~t~48| EXCEPTION ~q~n', [Name, E]), fail ))
	->  R = ok, format('  ok    ~w~n', [Name])
	;   R = failed, format('  FAIL  ~w~n', [Name])
	).

said(Result, Pattern) :-
	get_dict(lines, Result, Lines),
	member(L, Lines),
	sub_string(L, _, _, _, Pattern), !.

%  --- the door: a refusal explained, then the way through

test('a closed door refuses passage, and says why', (
	play_start(file('examples/if/doors.le'), [], Id),
	play_turn(Id, "e", R1),
	said(R1, "You can't go east"),
	play_turn(Id, "open the door", R2),
	said(R2, "You open the oak door"),
	play_turn(Id, "e", R3),
	said(R3, "Garden"),
	play_stop(Id) )).

test('the room description lists what is there and the exits', (
	play_start(file('examples/if/doors.le'), [], Id),
	play_status(Id, St),
	get_dict(transcript, St, [Opening|_]),
	get_dict(lines, Opening, OLines),
	member(L1, OLines), sub_string(L1, _, _, _, "Hall"),
	member(L2, OLines), sub_string(L2, _, _, _, "oak door"),
	play_turn(Id, "open door", _),
	play_turn(Id, "look", R),
	said(R, "Exits: east"),
	play_stop(Id) )).

%  --- the player's channel

test('a raw fluent is refused on the player''s channel', (
	play_start(file('examples/if/doors.le'), [], Id),
	play_turn(Id, "!carries(player, 'the oak door')", R),
	get_dict(refused, R, [_]),
	said(R, "does not carry"),
	play_status(Id, St),
	get_dict(state, St, State),
	\+ member("carries(player,'the oak door')", State),
	play_stop(Id) )).

test('a raw command term is accepted on the player''s channel', (
	play_start(file('examples/if/doors.le'), [], Id),
	play_turn(Id, "!cmd_open('the oak door')", R),
	get_dict(refused, R, []),
	said(R, "You open the oak door"),
	play_stop(Id) )).

%  --- the synonyms and the inventory

test('Inform''s short forms: x, i, get, z', (
	play_start(file('examples/if/nothing_as_term.le'), [], Id),
	play_turn(Id, "i", R1), said(R1, "You are carrying a box"),
	play_turn(Id, "get banana", R2), said(R2, "You take the banana"),
	play_turn(Id, "x box", R3), said(R3, "In it: a peach"),
	play_turn(Id, "z", R4), said(R4, "Time passes"),
	play_turn(Id, "put banana in box", R5), said(R5, "You put the banana into the box"),
	play_stop(Id) )).

test('an ambiguous noun asks which', (
	play_start(file('examples/if/negated_rp.le'), [], Id),
	play_turn(Id, "open box", R1), said(R1, "Which box do you mean"),
	play_turn(Id, "open jewel box", R2), said(R2, "You open the jewel box"),
	play_turn(Id, "open broken box", R3), said(R3, "You can't open the broken box"),
	play_stop(Id) )).

%  --- a character on an order, and why

test('a character fetches through a locked case on an order', (
	play_start(file('examples/if/iqtest.le'), [], Id),
	play_turn(Id, "open case", R1), said(R1, "the case is locked"),
	play_turn(Id, "og, get donuts", R2),
	said(R2, "Ogg unlocks the case"),
	said(R2, "Ogg opens the case"),
	said(R2, "Ogg takes the donuts"),
	play_turn(Id, "og, give donuts to me", R3), said(R3, "Ogg gives the donuts to you"),
	play_turn(Id, "eat donuts", R4), said(R4, "You eat the donuts"),
	play_stop(Id) )).

test('why answers on the last turn', (
	play_start(file('examples/if/iqtest.le'), [], Id),
	play_turn(Id, "open case", _),
	play_why(Id, last, Lines),
	member(L1, Lines), sub_string(L1, _, _, _, "why_not(happened(open(player,case))"),
	member(L2, Lines), sub_string(L2, _, _, _, "blocked_by_denial"),
	member(L3, Lines), sub_string(L3, _, _, _, "locked(case)"),
	play_stop(Id) )).

test('a story''s own command joins the parser', (
	play_start(file('examples/if/iqtest.le'), [], Id),
	play_allowed(Id, Allowed),
	memberchk('the_command_is_to_eat/1', Allowed),
	play_turn(Id, "eat donuts", R),
	said(R, "You can't eat the donuts"),
	play_stop(Id) )).

%  --- the turn has an end: every-turn rules and scheduled events

test('every-turn rules and scheduled events fire on the end of the turn', (
	play_start(file('examples/if/mre.le'), [], Id),
	play_turn(Id, "eat apple", R1), said(R1, "You eat the apple"),
	play_turn(Id, "z", _), play_turn(Id, "z", _), play_turn(Id, "z", R4),
	said(R4, "You complain"),
	play_stop(Id) )).

%  --- Alice: the book's path from the keyboard, and the fork at the bottle

test('Alice: the White Rabbit runs past and the hole goes one way', (
	play_start(file('examples/if/alice.le'), [], Id),
	play_turn(Id, "z", R1), said(R1, "I shall be late"),
	play_turn(Id, "wait", R2), said(R2, "rabbit-hole under the hedge"),
	play_turn(Id, "d", R3), said(R3, "very deep well"),
	play_turn(Id, "u", R4), said(R4, "You can't go up"),
	play_turn(Id, "down", R5), said_all(R5, ["CHAPTER II", "Hall"]),
	play_stop(Id) )).

test('Alice: drink, and the key is out of reach; eat, and cry a pool', (
	play_start(file('examples/if/alice.le'), [], Id),
	forall(member(T, ["z", "z", "d", "d"]), play_turn(Id, T, _)),
	play_turn(Id, "drink bottle", R1), said(R1, "shutting up like a telescope"),
	play_turn(Id, "take key", R2), said(R2, "far above your head"),
	play_turn(Id, "eat cake", R3), said_all(R3, ["nine feet high", "large pool"]),
	play_turn(Id, "z", R4), said(R4, "drops the white kid gloves and the fan"),
	play_turn(Id, "take fan", R5), said(R5, "You take the fan"),
	play_turn(Id, "wave fan", R6), said_all(R6, ["shrinking rapidly", "up to your chin", "end of chapter II"]),
	play_stop(Id) )).

test('Alice: a fork at the bottle, and the diff between the two games', (
	play_start(file('examples/if/alice.le'), [], A),
	forall(member(T, ["z", "z", "d", "d"]), play_turn(A, T, _)),
	play_fork(A, B),
	play_turn(A, "drink bottle", _),
	play_turn(B, "take key", RB1), said(RB1, "tiny golden key"),
	play_turn(B, "drink bottle", _),
	play_turn(B, "unlock door with key", RB2), said(RB2, "The key fits"),
	play_turn(B, "open door", _),
	play_turn(B, "s", RB3), said_all(RB3, ["loveliest garden", "differently"]),
	play_diff(A, B, Lines),
	member(L1, Lines), sub_string(L1, _, _, _, "You take the golden key"),
	member(L2, Lines), sub_string(L2, _, _, _, "You go south"),
	play_status(A, SA), get_dict(state, SA, StateA),
	memberchk("in(player,hall)", StateA),
	play_status(B, SB), get_dict(state, SB, StateB),
	memberchk("in(player,garden)", StateB),
	play_list(Games),
	member(G, Games), get_dict(play, G, B), get_dict(parent, G, A),
	play_stop(A), play_stop(B) )).

test('Alice: a constant named as a phrase is found by its words and told by its name', (
	play_start(file('examples/if/alice.le'), [], Id),
	play_turn(Id, "z", _),
	play_turn(Id, "x the white rabbit", R1), said(R1, "about the White Rabbit"),
	play_turn(Id, "d", R2), said(R2, "The Rabbit Hole"),
	play_turn(Id, "d", _),
	play_commands(Id, Cs), findall(T, (member(C, Cs), get_dict(text, C, T)), Ts),
	memberchk("take the golden key", Ts), memberchk("examine the small door", Ts),
	play_turn(Id, "take key", R3), said(R3, "tiny golden key"),
	play_turn(Id, "drop the golden key", R4), said(R4, "You drop the golden key"),
	play_stop(Id) )).

%  --- the same story without the clock: no turn markers, the same states

test('Alice without turns: driven by its commands alone, to the same end', (
	play_start(file('examples/if/alice_pure_lps.le'), [], Id),
	%  the Rabbit runs past and goes down before the first prompt
	play_status(Id, St0), get_dict(transcript, St0, [Op|_]), get_dict(lines, Op, OL),
	member(L1, OL), sub_string(L1, _, _, _, "I shall be late"),
	member(L2, OL), sub_string(L2, _, _, _, "rabbit-hole under the hedge"),
	play_turn(Id, "d", R1), said_all(R1, ["very deep well", "scurries away"]),
	play_turn(Id, "d", R2), said_all(R2, ["CHAPTER II", "no longer to be seen"]),
	play_turn(Id, "drink bottle", R3), said(R3, "shutting up like a telescope"),
	play_turn(Id, "take key", R4), said(R4, "far above your head"),
	%  everything the cake causes, in one burst: tears, the Rabbit back, the fan dropped
	play_turn(Id, "eat cake", R5),
	said_all(R5, ["nine feet high", "large pool", "the White Rabbit returns", "drops the white kid gloves"]),
	play_turn(Id, "take fan", R6), said(R6, "You take the fan"),
	play_turn(Id, "wave fan", R7), said_all(R7, ["shrinking rapidly", "up to your chin", "end of chapter II"]),
	%  no clock in the state, and no turn markers in the events
	play_status(Id, St), get_dict(state, St, State),
	\+ ( member(F, State), sub_string(F, 0, _, _, "turn(") ),
	memberchk("in(player,'the pool of tears')", State),
	get_dict(events, R7, Evs), \+ memberchk("begin_turn", Evs),
	play_stop(Id) )).

%  --- what can be done now: contextual, tried on a copy of the game

test('the commands offered are the ones that would work now', (
	play_start(file('examples/if/doors.le'), [], Id),
	play_commands(Id, C1), findall(T, (member(C, C1), get_dict(text, C, T)), T1),
	memberchk("open the oak door", T1), \+ memberchk("go east", T1), memberchk("look", T1),
	play_turn(Id, "open door", _),
	play_commands(Id, C2), findall(T, (member(C, C2), get_dict(text, C, T)), T2),
	memberchk("go east", T2), \+ memberchk("open the oak door", T2), memberchk("close the oak door", T2),
	play_stop(Id) )).

test('an order to a character is offered when it would work', (
	play_start(file('examples/if/iqtest.le'), [], Id),
	play_commands(Id, Cs), findall(T, (member(C, Cs), get_dict(text, C, T)), Ts),
	%  the donuts are in a closed case, out of anyone's sight: no order yet
	\+ memberchk("open the case", Ts), \+ memberchk("ogg, get the donuts", Ts),
	play_turn(Id, "og, get donuts", _),
	play_commands(Id, Cs2), findall(T, (member(C, Cs2), get_dict(text, C, T)), Ts2),
	memberchk("ogg, give the donuts to me", Ts2),
	play_stop(Id) )).

test('turns carry their cycles, and a thing''s last change names its turn', (
	play_start(file('examples/if/doors.le'), [], Id),
	play_turn(Id, "open the door", R1), get_dict(cycles, R1, [A1, B1]), A1 =< B1,
	play_turn(Id, "e", R2), get_dict(cycles, R2, [A2, B2]), A2 =:= B1 + 1, A2 =< B2,
	play_status(Id, St), get_dict(transcript, St, [Op, E1, E2]),
	get_dict(cycles, Op, [0, Z]), Z =:= A1 - 1,
	get_dict(cycles, E1, [A1, B1]), get_dict(cycles, E2, [A2, B2]),
	%  the player was last seen changing on the turn that went east
	play_last_change(Id, "in(player,garden)", 1000, L),
	get_dict(turn, L, 2), get_dict(cycle, L, C), A2 =< C, C =< B2,
	get_dict(changed, L, Ch), memberchk("in(player,garden)", Ch),
	%  asked as of the first turn: the door opened then
	play_last_change(Id, "closed('the oak door')", B1, L1), get_dict(turn, L1, 1),
	%  a thing nothing ever happened to: the other name in its term answers
	play_last_change(Id, "in(fern,hall)", 1000, L2), get_dict(things, L2, [hall]),
	%  and as of the opening, nothing about anyone had changed yet
	play_last_change(Id, "in(player,hall)", 1, L3), get_dict(cycle, L3, -1),
	play_stop(Id) )).
