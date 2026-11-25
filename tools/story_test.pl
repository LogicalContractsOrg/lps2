/* story_test.pl — the run as a story (src/edges/lps_story.pl), which the
   Comics pane draws.

   Two halves, and neither calls a language model:

     1. the story computed from the trace of examples/collections/kowalski-book/fox_crow.lps:
        its panels, the rule behind each action, the fluents that each event
        starts and ends, the latent actors, what did not happen;
     2. the check that a caption of a model must pass before the pane shows
        it: a number or a name of the program that the panel does not have
        refuses the caption;
     3. the exploratory story's "what if?": a run told again with an event
        left out or an event added, and a sentence read back as its term.

   Usage:
     ./myswipl.sh -q -g "consult('tools/story_test.pl')" -g "story_test:main" -t halt
*/

:- module(story_test, [main/0]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- consult('../src/lps.pl').
:- use_module('../src/core/lps_session').
:- use_module('../src/edges/lps_story').
:- use_module('../src/edges/lps_wording').

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
	what_if_checks,
	aggregate_all(count, failed(_), NF),
	format('~n=== story: ~w failed ===~n', [NF]),
	( NF =:= 0 -> true ; halt(1) ).

%	The exploratory story's "what if?": the run of examples/start/cafe.lps
%	told again with one difference (lps_session_alternative/5), and a
%	sentence of a document read back as its term (lps_worded_term/3).
what_if_checks :-
	lps_cli:compile_source(legacy, 'examples/start/cafe.lps', [], P, _),
	lps_session_new(P, [], S0),
	lps_session_run(S0, end, S, _),
	events_at(S, 3, E3),
	check('in the run, carl arrives at cycle 3', memberchk(arrives(carl), E3)),
	lps_session_alternative(S, [arrives(carl)], [], 3, A1),
	check('left out, carl does not arrive, and nobody serves him',
	      \+ ( events_at(A1, _, Es), ( member(arrives(carl), Es) ; member(serve(carl), Es) ) )),
	check('the other run has the same past: the cafe opens at cycle 2',
	      ( events_at(A1, 2, E2), memberchk(opens, E2) )),
	lps_session_alternative(S, [], [arrives(dora)], 3, A2),
	check('an event that is added is in the trace at its cycle',
	      ( events_at(A2, 3, E3b), memberchk(arrives(dora), E3b), memberchk(arrives(carl), E3b) )),
	check('the run itself is as it was',
	      ( events_at(S, 3, E3c), \+ memberchk(arrives(dora), E3c) )),
	lps_wording:lps_wording([le_template(transfer/3, event, "*a payer* transfers *an amount* to *a payee*", [], pos(1, 0, 0, 0), []),
				 le_template(cancel/0, action, "the lender calls off the loan", [], pos(2, 0, 0, 0), [])], W),
	check('a sentence of the document is read back as its term',
	      ( lps_wording:lps_worded_term(W, "Bob transfers 10 to Fariba.", T1), T1 == transfer(bob, 10, fariba) )),
	check('a sentence with no slot is read back as its term',
	      ( lps_wording:lps_worded_term(W, "the lender calls off the loan", T2), T2 == cancel )),
	check('words of no template are not an event',
	      \+ lps_wording:lps_worded_term(W, "bob pays fariba", _)).

events_at(S, C, Es) :-
	lps_session_trace(S, Trace),
	member(stage(events, C, Es), Trace).

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
