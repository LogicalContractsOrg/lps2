/* story_test.pl — the run as a story (src/edges/lps_story.pl), which the
   Comics pane draws.

   Two halves, and neither calls a language model:

     1. the story computed from the trace of examples/collections/kowalski-book/fox_crow.lps:
        its panels, the rule behind each action, the fluents that each event
        starts and ends, the latent actors, what did not happen;
     2. the check that a caption of a model must pass before the pane shows
        it: a number or a name of the program that the panel does not have
        refuses the caption.

   Usage:
     ./myswipl.sh -q -g "consult('tools/story_test.pl')" -g "story_test:main" -t halt
*/

:- module(story_test, [main/0]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- consult('../src/lps.pl').
:- use_module('../src/core/lps_session').
:- use_module('../src/edges/lps_story').

:- dynamic failed/1.

main :-
	retractall(failed(_)),
	board(standard, B), board(exploratory, X),
	g(B, panels, BP), g(X, panels, XP), g(B, latent, BL), g(X, silences, XS), g(B, names, BN),
	check('five panels: the start, three cycles with events, the end', length(BP, 5)),
	check('the exploratory story adds what did not happen', ( length(XP, 6), last(XP, L), g(L, kind, "silence") )),
	nth1(2, BP, P2), nth1(3, BP, P3),
	g(P2, events, P2E), g(P3, events, P3E),
	check('the first event is praise(fox, crow), an action of the fox',
	      ( P2E = [E], g(E, term, "praise(fox, crow)"), g(E, kind, "action"), g(E, agent, "fox") )),
	check('the praise starts sings(crow)',
	      ( P2E = [E2], g(E2, changes, [C]), g(C, kind, "initiated"), g(C, fluent, "sings(crow)") )),
	check('two actions from cycle 2 to cycle 3', ( length(P3E, 2), g(P3, from, 2), g(P3, to, 3) )),
	check('the drop is the work of the rule with no agent',
	      ( member(E3, P3E), g(E3, term, "drop(crow, cheese)"), g(E3, rules, [Line]),
		member(R, BL), g(R, kind, "rule"), g(R, line, Line), g(R, agent, null) )),
	check('the rule of the fox has the fox as its agent, and fired twice',
	      ( member(R2, BL), g(R2, kind, "rule"), g(R2, agent, "fox"), g(R2, acted, 2) )),
	check('the constraint never refuses', ( member(G, BL), g(G, kind, "constraint"), g(G, acted, 0) )),
	check('nothing ends sings(crow)', ( member(S, XS), g(S, what, "fluent"), g(S, term, "sings(crow)") )),
	check('has(fox, cheese) can end: a drop ends it', \+ ( member(S2, XS), g(S2, term, "has(fox, cheese)") )),
	check('the names: the cheese, the crow, the fox, the ground',
	      ( findall(N, ( member(D, BN), g(D, name, N) ), Ns), msort(Ns, ["cheese", "crow", "fox", "ground"]) )),
	check('a caption of the facts passes',
	      \+ lps_story:caption_fault(B, P2, "The fox praises the crow. The crow starts to sing.", _)),
	check('a name that the panel does not have is refused',
	      ( lps_story:caption_fault(B, P2, "The fox praises the crow for the cheese.", W1), sub_string(W1, _, _, _, "cheese") )),
	check('a number that the panel does not have is refused',
	      ( lps_story:caption_fault(B, P2, "The fox praises the crow 3 times.", W2), sub_string(W2, _, _, _, "3") )),
	check('speech is refused', lps_story:caption_fault(B, P2, "The fox says \"what a voice\".", _)),
	check('the answer of a model is read out of the text around it',
	      ( lps_story:reply_json("Here it is:\n```json\n{\"title\": \"T\"}\n```", J), g(J, title, "T") )),
	check('an answer with a figure that does not exist loses that figure only',
	      ( lps_story:checked(B, _{title: "T", cast: _{fox: _{fig: "fox"}, crow: _{fig: "dragon"}}, captions: [], sfx: []}, Wd, Fs),
		g(Wd, cast, Cast), get_dict(fox, Cast, _), \+ get_dict(crow, Cast, _), length(Fs, 5) )),
	aggregate_all(count, failed(_), NF),
	format('~n=== story: ~w failed ===~n', [NF]),
	( NF =:= 0 -> true ; halt(1) ).

board(Mode, Board) :-
	lps_cli:compile_source(legacy, 'examples/collections/kowalski-book/fox_crow.lps', [], P, _),
	lps_session_new(P, [], S0),
	lps_session_run(S0, end, S, _),
	lps_session_actions(S, Lane),
	story_board(S, Lane, [], Mode, Board).

g(Dict, Key, Value) :- get_dict(Key, Dict, Value).

check(Name, Goal) :-
	(   catch(Goal, E, ( print_message(error, E), fail ))
	->  format('  ok    ~w~n', [Name])
	;   format('  FAIL  ~w~n', [Name]), assertz(failed(Name))
	).
