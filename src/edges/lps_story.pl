/* lps_story.pl — a run as a story: what the Comics pane draws.

   The Timeline shows what happened. A story of a run also says three things
   that the Timeline does not show:

     - who acts when the program names nobody. A reactive rule, a causal law
       and an integrity constraint each do something in a run, and none of
       them is an actor in the text. These are the *latent actors*;
     - what was refused: an action that a constraint blocked leaves no mark
       on the Timeline (the trace has it: `action_blocked/5`);
     - what did not happen: a rule that never fired, a constraint that never
       refused, a fluent that holds at the end and that no causal law ends.

   Two halves, and only the second calls a language model.

     story_board/5   the story, computed from the trace: the panels (one for
                     each cycle in which something happened, one for the
                     start, one for the end), each with its events, the
                     fluents that the events started and ended, the rule
                     behind each action, the refusals, and a caption made of
                     those. Nothing in it is written by a model, so nothing
                     in it can say what the run did not do.

     story_words/5   words for that story, from a small model: a title, a
                     figure for each name of the program, a name for each
                     latent actor, a caption for each panel. Each caption is
                     checked against the panel it is for: a number or a name
                     of the program that the panel does not have refuses the
                     caption, the model is asked once more, and a caption
                     refused twice is dropped (the reader of the reply keeps
                     the computed one).

   The model writes no speech and no geometry. What an actor "says" in a
   panel is the event itself, in the words of its template when the document
   is Logical English and as the term otherwise; where a figure stands is
   the pane's business (ui/src/panes/comic.js).

   The experiment behind this is lpsPlus docs/reports/ProgramStoriesExperiment.md.
*/

:- module(lps_story, [
	story_board/5,           % +Session, +ActionLane, +Wording, +Mode, -Board (dict)
	story_words/5,           % +Board, +Clauses (dict Line-Text), +Options, -Words (dict), -Note
	story_figures/1          % -Names of the figures a model may choose
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(http/json)).
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../core/lps_explain', [trace_stage/4, trace_cycles/2]).
:- use_module(lps_wording).
:- use_module(lps_llm).

%	At most this many panels between the first and the last: past that a
%	strip is a film nobody reads, and neighbouring cycles share a panel.
max_beats(14).

		 /*******************************
		 *	      the board		*
		 *******************************/

%!	story_board(+Session, +ActionLane, +Wording, +Mode, -Board) is det.
%
%	Mode is `standard` or `exploratory`. The exploratory story adds what
%	did not happen in the run.
story_board(S, lane(_, ActionCells), Wording, Mode, Board) :-
	lps_session_program(S, P),
	lps_session_trace(S, Trace),
	trace_cycles(Trace, Max),
	( catch(lps_session_outcome(S, O), _, fail) -> true ; O = unknown ),
	Ctx = ctx(P, Trace, Wording, ActionCells),
	busy_cycles(Trace, Max, Busy),
	max_beats(Cap),
	chunks(Busy, Cap, Chunks),
	start_panel(Ctx, Start),
	beat_panels(Ctx, Chunks, 0, Beats),
	( last(Busy, LastBusy) -> true ; LastBusy = 1 ),
	end_panel(Ctx, LastBusy, Max, O, End),
	latent_actors(Ctx, Latent),
	silences(Ctx, Max, Silences),
	(   Mode == exploratory, Silences \== []
	->  Extra = [_{kind: "silence", from: Max, to: Max, items: Silences,
		       caption: "What did not happen in this run."}]
	;   Extra = []
	),
	append([[Start|Beats], [End], Extra], Panels),
	names(Trace, Names),
	( Wording == [] -> English = false ; English = true ),
	atom_string(O, OS), atom_string(Mode, MS),
	Board = _{ok: true, cycles: Max, outcome: OS, english: English, mode: MS,
		  panels: Panels, latent: Latent, names: Names, silences: Silences}.

%	The cycles at which an event happened or an action was refused.
busy_cycles(Trace, Max, Busy) :-
	findall(T, ( between(1, Max, T),
		     (   trace_stage(Trace, events, T, [_|_])
		     ;   refusal_record(Trace, T, _, _, _)
		     ) ),
		Ts),
	sort(Ts, Busy).

chunks(Busy, Cap, Chunks) :-
	length(Busy, N),
	(   N =< Cap
	->  maplist([T, [T]]>>true, Busy, Chunks)
	;   Size is (N + Cap - 1) // Cap,
	    chunk(Busy, Size, Chunks)
	).

chunk([], _, []) :- !.
chunk(L, Size, [C|Cs]) :-
	length(L, N), K is min(N, Size),
	length(C, K), append(C, Rest, L),
	chunk(Rest, Size, Cs).

start_panel(ctx(_, Trace, W, _), _{kind: "start", from: 1, to: 1, holds: Texts, caption: Cap}) :-
	(   trace_stage(Trace, fluents, 1, Fs) -> true
	;   trace_stage(Trace, fluents, 0, Fs) -> true
	;   Fs = []
	),
	maplist(said(W), Fs, Texts),
	(   Texts == []
	->  Cap = "At the start no fluent holds."
	;   some(Texts, 5, Shown),
	    format(string(Cap), "At the start: ~w.", [Shown])
	).

beat_panels(_, [], _, []).
beat_panels(Ctx, [Cycles|Rest], Prev, [Panel|Panels]) :-
	Cycles = [First|_], last(Cycles, Last),
	From is First - 1,
	Ctx = ctx(_, Trace, _, _),
	findall(E, ( member(T, Cycles), trace_stage(Trace, events, T, Es),
		     member(Ev, Es), event_dict(Ctx, T, Ev, E) ),
		Events),
	findall(R, ( member(T, Cycles), refusal_dict(Ctx, T, R) ), Refusals),
	findall(C, ( member(T, Cycles), composite_dict(Ctx, T, C) ), Composites),
	Quiet is max(0, From - max(Prev, 1)),
	beat_caption(Events, Refusals, Cap),
	Panel = _{kind: "beat", from: From, to: Last, quiet_before: Quiet,
		  events: Events, refusals: Refusals, composites: Composites, caption: Cap},
	beat_panels(Ctx, Rest, Last, Panels).

end_panel(ctx(_, Trace, W, _), LastBusy, Max, O,
	  _{kind: "end", from: LastBusy, to: Max, holds: Texts, outcome: OS, caption: Cap}) :-
	( trace_stage(Trace, fluents, Max, Fs) -> true ; Fs = [] ),
	maplist(said(W), Fs, Texts),
	atom_string(O, OS),
	( Texts == [] -> Shown = "no fluent holds" ; some(Texts, 5, Shown) ),
	(   Max > LastBusy
	->  format(string(Cap), "No event from cycle ~w to cycle ~w. At the end: ~w.", [LastBusy, Max, Shown])
	;   format(string(Cap), "The run ends. At the end: ~w.", [Shown])
	).

%	One event of the run: what it is, who did it, why, and what it changed.
event_dict(Ctx, T, E, D) :-
	Ctx = ctx(P, Trace, W, ActionCells),
	Cycle is T - 1,
	term_text(E, TS), said(W, E, Text),
	(   memberchk(cell(T, Acts), ActionCells), member(A, Acts), A =@= E
	->  Kind = "action"
	;   Kind = "observed"
	),
	agent_of(E, Agent),
	term_names(E, Ns), maplist(atom_string, Ns, Names),
	( Kind == "action" -> rule_lines(P, Trace, Cycle, E, Rules) ; Rules = [] ),
	findall(_{kind: KS, fluent: FS, text: FT, line: Line},
		( member(state_change(Cycle, K, F, happens(E0, _, _), Law), Trace),
		  E0 =@= E,
		  atom_string(K, KS), term_text(F, FS), said(W, F, FT),
		  law_line(P, K, Law, Line) ),
		Changes0),
	list_to_set(Changes0, Changes),
	D = _{cycle: T, term: TS, text: Text, kind: Kind, agent: Agent, names: Names,
	      rules: Rules, changes: Changes}.

agent_of(E, Agent) :-
	(   compound(E), arg(1, E, A), atom(A), A \== []
	->  atom_string(A, Agent)
	;   Agent = null
	).

law_line(P, Kind, Law, Line) :-
	(   integer(Law), p_clause_src(P, Kind, Law, _, src(_, Line, _, _)), in_document(Line)
	->  true
	;   Line = null
	).

%	The lines of the reactive rules behind an action: the rules whose
%	consequent names the action, or a composite event that the action is a
%	part of. Two rules can have the same consequent (the escrow pays the
%	buyer by one rule and the seller by the next); the one whose antecedent
%	events are in the run is kept.
rule_lines(P, Trace, Cycle, E, Lines) :-
	findall(Comp, ( member(action_ancestor(Cycle, Act, Comp, _, _), Trace), Act =@= E ), Comps),
	findall(Cons,
		( member(rule_fired(C0, _, Cons), Trace), C0 =< Cycle,
		  (   in_consequent(Cons, E)
		  ;   member(Comp, Comps), in_consequent(Cons, Comp)
		  ) ),
		Conss0),
	sort(Conss0, Conss),
	findall(Line, ( member(Cons, Conss), cons_line(P, Trace, Cons, Line) ), Lines0),
	sort(Lines0, Lines).

%	A clause is in the document when it has a line there. A clause that a
%	document takes from a library (the interactive fiction library, for
%	one) has line 0: the story does not make an actor of it, because the
%	reader has no text to read behind that actor.
in_document(Line) :- integer(Line), Line > 0.

%	A line of a reactive rule that a recorded consequent can come from.
cons_line(P, Trace, Cons, Line) :-
	findall(L-Ant, ( p_clause_src(P, reactive_rule, _, reactive_rule(Ant, RC), src(_, L, _, _)),
			 in_document(L), \+ RC \= Cons, RC = Cons ),
		Cands),
	(   Cands = [Line-_]
	->  true
	;   include(cand_in_run(Trace), Cands, Kept),
	    Kept = [_|_]
	->  member(Line-_, Kept)
	;   member(Line-_, Cands)
	).

cand_in_run(Trace, _-Ant) :- antecedent_in_run(Trace, Ant).

in_consequent(C, A) :- is_list(C), !, member(X, C), in_consequent(X, A).
in_consequent(happens(E, _, _), A) :- \+ E \= A.

antecedent_in_run(Trace, Ant) :-
	forall(member(happens(E, _, _), Ant),
	       ( trace_stage(Trace, events, _, Es), member(X, Es), \+ X \= E )).

%	An action of the program that a constraint refused, or an observed
%	event that one refused. T is the cycle at which it would have happened.
refusal_record(Trace, T, E, Conds, Kind) :-
	(   member(action_blocked(C, E, _, _, Conds), Trace), Kind = action
	;   member(observation_refused(C, Es, Conds), Trace), member(E, Es), Kind = observed
	),
	T is C + 1.

refusal_dict(ctx(P, Trace, W, _), T, D) :-
	findall(r(E, Conds, Kind), refusal_record(Trace, T, E, Conds, Kind), Rs0),
	variant_set(Rs0, Rs),
	member(r(E, Conds, Kind), Rs),
	term_text(E, TS), said(W, E, Text),
	agent_of(E, Agent),
	term_names(E, Ns), maplist(atom_string, Ns, Names),
	denial_line(P, Conds, Line),
	findall(BT, ( member(happens(B, _, _), Conds), B \=@= E, said(W, B, BT) ), ByEvents),
	findall(HT, ( member(holds(H, _), Conds), holds_text(W, H, HT) ), ByState),
	atom_string(Kind, KS),
	D = _{cycle: T, term: TS, text: Text, kind: KS, agent: Agent, names: Names, line: Line,
	      with_events: ByEvents, with_state: ByState}.

holds_text(W, not(F), T) :- !, said(W, F, T0), format(string(T), "it is not the case that ~w", [T0]).
holds_text(W, F, T) :- said(W, F, T).

denial_line(P, Conds, Line) :-
	(   p_clause_src(P, d_pre, _, Term, src(_, Line, _, _)),
	    ( Term = d_pre(Cs) -> true ; Cs = Term ),
	    \+ Cs \= Conds
	->  ( in_document(Line) -> true ; Line = null )
	;   Line = null
	).

composite_dict(ctx(_, Trace, W, _), T, _{term: TS, text: Text, from: T1, to: T2}) :-
	trace_stage(Trace, composites, T, Items),
	member(happens(E, T1, T2), Items),
	term_text(E, TS), said(W, E, Text).

beat_caption(Events, Refusals, Cap) :-
	findall(T, ( member(E, Events), get_dict(text, E, T) ), ETs),
	findall(T, ( member(E, Events), member(C, E.changes), C.kind == "initiated", T = C.text ), Starts),
	findall(T, ( member(E, Events), member(C, E.changes), C.kind == "terminated", T = C.text ), Ends),
	findall(T, ( member(E, Events), member(C, E.changes), C.kind == "updated", T = C.text ), Sets),
	findall(T, ( member(R, Refusals), get_dict(text, R, T) ), RTs),
	findall(S,
		(   ETs \== [], some(ETs, 4, X), sentence(X, S)
		;   Starts \== [], some(Starts, 3, X), format(string(S), "Starts: ~w.", [X])
		;   Ends \== [], some(Ends, 3, X), format(string(S), "Ends: ~w.", [X])
		;   Sets \== [], some(Sets, 3, X), format(string(S), "Changes: ~w.", [X])
		;   RTs \== [], some(RTs, 3, X), format(string(S), "Refused: ~w.", [X])
		),
		Ss),
	atomic_list_concat(Ss, ' ', A), atom_string(A, Cap).

sentence(X, S) :-
	sub_string(X, 0, 1, _, F), string_upper(F, FU),
	sub_string(X, 1, _, 0, Rest),
	format(string(S), "~w~w.", [FU, Rest]).

%	The first N of a list of texts, as one text, with what was left out.
some(Texts, N, Shown) :-
	length(Texts, Len),
	(   Len =< N
	->  atomic_list_concat(Texts, '; ', A)
	;   length(Head, N), append(Head, _, Texts),
	    atomic_list_concat(Head, '; ', A0),
	    More is Len - N,
	    format(atom(A), '~w; and ~w more', [A0, More])
	),
	atom_string(A, Shown).

		 /*******************************
		 *	 the latent actors	*
		 *******************************/

%	One for each reactive rule, one for the causal laws together, one for
%	each integrity constraint, each with how often it acted in the run.
latent_actors(ctx(P, Trace, _, _), Latent) :-
	findall(D, rule_actor(P, Trace, D), Rules),
	findall(L, ( member(state_change(_, K, _, _, Law), Trace), law_line(P, K, Law, L), integer(L) ), Ls0),
	sort(Ls0, LawLines),
	findall(x, member(state_change(_, _, _, _, _), Trace), Uses), length(Uses, NU),
	(   p_clause_src(P, Fam, _, _, _), memberchk(Fam, [initiated, terminated, updated])
	->  World = [_{id: "world", kind: "law", lines: LawLines, acted: NU}]
	;   World = []
	),
	findall(D, guard_actor(P, Trace, D), Guards),
	append([Rules, World, Guards], Latent).

rule_actor(P, Trace, _{id: Id, kind: "rule", line: Line, agent: Agent, acted: N, actions: Fs}) :-
	p_clause_src(P, reactive_rule, _, reactive_rule(_, RC), src(_, Line, _, _)),
	in_document(Line),
	format(string(Id), "rule~w", [Line]),
	findall(Id0, ( member(rule_fired(_, Id0, Cons), Trace), \+ RC \= Cons,
		       \+ \+ cons_line(P, Trace, Cons, Line) ), Xs0),
	sort(Xs0, Xs), length(Xs, N),
	findall(A, ( member(happens(E, _, _), RC), compound(E), arg(1, E, A) ), Firsts),
	(   Firsts = [A1|_], atom(A1), A1 \== [], forall(member(X, Firsts), X == A1),
	    findall(E, member(happens(E, _, _), RC), AllE), length(AllE, NE), length(Firsts, NE)
	->  atom_string(A1, Agent)
	;   Agent = null
	),
	findall(F, ( member(happens(E, _, _), RC), callable(E), functor(E, F0, _), atom_string(F0, F) ), Fs0),
	list_to_set(Fs0, Fs).

guard_actor(P, Trace, _{id: Id, kind: "constraint", line: Line, acted: N, watches: Ws}) :-
	p_clause_src(P, d_pre, _, Term, src(_, Line, _, _)),
	in_document(Line),
	( Term = d_pre(Cs) -> true ; Cs = Term ),
	is_list(Cs),
	format(string(Id), "guard~w", [Line]),
	findall(x, ( refusal_record(Trace, _, _, Conds, _), \+ Cs \= Conds ), Xs0),
	length(Xs0, N),
	findall(W, ( member(happens(E, _, _), Cs), callable(E), functor(E, F, _), atom_string(F, W) ), Ws0),
	list_to_set(Ws0, Ws).

%	What did not happen: a rule that never fired, a constraint that never
%	refused, a fluent that holds at the end and that no causal law can end.
silences(ctx(P, Trace, W, _), Max, Silences) :-
	findall(_{what: "rule", line: Line},
		( rule_actor(P, Trace, D), D.acted =:= 0, Line = D.line ), S1),
	findall(_{what: "constraint", line: Line},
		( guard_actor(P, Trace, D), D.acted =:= 0, Line = D.line ), S2),
	( trace_stage(Trace, fluents, Max, Fs) -> true ; Fs = [] ),
	findall(_{what: "fluent", text: T, term: TS},
		( member(F, Fs), \+ can_end(P, F), said(W, F, T), term_text(F, TS) ), S3),
	append([S1, S2, S3], Silences).

can_end(P, F) :- catch(p_terminated(P, _, F0, _), _, fail), \+ F0 \= F, !.
can_end(P, F) :- catch(p_updated(P, _, F0, _, _), _, fail), \+ F0 \= F, !.

%	The names of the run: each constant in an event or in a fluent, with how
%	often it is the first argument of an event (it acts) and how often it
%	is mentioned at all. Most mentioned first, twelve at most.
names(Trace, Names) :-
	findall(N-act, ( member(stage(events, _, Es), Trace), member(E, Es),
			 compound(E), arg(1, E, N), atom(N), N \== [] ), Acts),
	findall(N-in, ( member(stage(St, _, Is), Trace), memberchk(St, [events, fluents]),
			member(I, Is), term_names(I, Ns), member(N, Ns) ), Ins),
	findall(N, member(N-_, Ins), All0), sort(All0, All),
	findall(M-_{name: NS, acts: A, mentions: M},
		( member(N, All),
		  aggregate_all(count, member(N-act, Acts), A),
		  aggregate_all(count, member(N-in, Ins), M),
		  atom_string(N, NS) ),
		Pairs),
	sort(1, @>=, Pairs, Sorted),
	pairs_values(Sorted, Ns0),
	( length(Ns0, Len), Len > 12 -> length(Names, 12), append(Names, _, Ns0) ; Names = Ns0 ).

%	The constants of a term: the atoms among its arguments, at any depth.
term_names(T, Ns) :-
	(   compound(T)
	->  findall(A, ( sub_term(A, T), atom(A), A \== [] ), As)
	;   As = []
	),
	list_to_set(As, Ns).

		 /*******************************
		 *	      wording		*
		 *******************************/

term_text(T, S) :-
	copy_term(T, T1), numbervars(T1, 0, _),
	format(string(S), '~W', [T1, [quoted(true), numbervars(true), spacing(next_argument)]]).

%	A term in the words of its document, or as the term.
said(Wording, T, S) :-
	(   Wording \== [], catch(lps_worded(Wording, T, S0), _, fail)
	->  S = S0
	;   term_text(T, S)
	).

variant_set([], []).
variant_set([X|Xs], [X|Ys]) :-
	exclude([Y]>>(Y =@= X), Xs, Xs1),
	variant_set(Xs1, Ys).

		 /*******************************
		 *	the model's words	*
		 *******************************/

%!	story_figures(-Names) is det.
%
%	The figures that the pane can draw. A model chooses among these names;
%	any other answer is dropped.
story_figures([person, woman, child, animal, fox, bird, robot, machine, vehicle, boat,
	       building, door, safe, parcel, paper, coins, food, fork, tool, lamp, box, none]).

%!	story_words(+Board, +Clauses, +Options, -Words, -Note) is det.
%
%	Options: model(M), api_key(K), actors(standard|diverse). Words has
%	`title`, `cast` (a figure for each name), `latent` (a name for each
%	latent actor; only with actors(diverse)), `captions` (one for each
%	panel, or null where none passed the check) and `sfx`. Note says what
%	was dropped, for the reader of the reply.
story_words(Board, Clauses, Options, Words, Note) :-
	memberchk(model(Model), Options),
	memberchk(api_key(Key), Options),
	( memberchk(actors(Actors), Options) -> true ; Actors = standard ),
	system_prompt(Actors, System),
	user_prompt(Board, Clauses, Actors, User),
	ask(Model, Key, [role(system, System), role(user, User)], D1),
	checked(Board, D1, W1, Faults1),
	(   Faults1 == []
	->  Words = W1, Note = ""
	;   repair_prompt(Faults1, Repair),
	    with_output_to(string(Prev), json_write_dict(current_output, D1, [width(0)])),
	    (   catch(ask(Model, Key, [role(system, System), role(user, User),
				       role(assistant, Prev), role(user, Repair)], D2), _, fail)
	    ->  checked(Board, D2, W2, Faults2),
		merge_words(W1, W2, Words),
		length(Faults2, N2)
	    ;   Words = W1, length(Faults1, N2)
	    ),
	    (   N2 =:= 0 -> Note = ""
	    ;   format(string(Note), "~w caption(s) of the model did not agree with the run and were left out", [N2])
	    )
	).

ask(Model, Key, Messages, Dict) :-
	llm_request(Model, Messages, Reply, [api_key(Key), max_tokens(3000), timeout(90)]),
	(   reply_json(Reply, Dict)
	->  true
	;   throw(error(story_words('the model did not answer with JSON'), _))
	).

reply_json(Text, Dict) :-
	( string(Text) -> T = Text ; format(string(T), "~w", [Text]) ),
	sub_string(T, B, _, _, "{"), !,
	string_length(T, L),
	( sub_atom_last(T, "}", E) -> true ; E is L - 1 ),
	Len is E - B + 1, Len > 1,
	sub_string(T, B, Len, _, J),
	catch(( open_string(J, In), json_read_dict(In, Dict, []) ), _, fail),
	is_dict(Dict).

sub_atom_last(T, Sub, Pos) :-
	findall(P, sub_string(T, P, _, _, Sub), Ps), Ps \== [], last(Ps, Pos).

system_prompt(Actors, S) :-
	story_figures(Figs), atomic_list_concat(Figs, ', ', FigList),
	(   Actors == diverse
	->  Latent = "- \"latent\": an object. For each latent actor, by its id, a short name from the domain of the program (2 or 3 words, with its article), taken from the world of this program and not from another one: a name for a rule says what the rule wants (\"the habit\", \"the appetite\"), a name for the causal laws says who keeps the record (\"the world\", \"the ledger\"), a name for a constraint says who refuses (\"the waiter\", \"the clerk\"). Two latent actors must not have the same name.\n"
	;   Latent = ""
	),
	format(string(S),
"You write the words of a comic strip that tells one run of a program in LPS (Logic Production Systems). The facts of the run are given to you as JSON. You do not decide what happened: you choose figures, and you write one caption for each panel.

Answer with one JSON object and nothing else. Its fields:
- \"title\": a title for the strip, at most 6 words.
- \"cast\": an object. For each name of the program, {\"fig\": F}, with F one of: ~w. Choose the figure nearest to what the name is. Use \"none\" for a name that is a value or a place and not a thing to draw. Use \"person\" for a name of a person.
~w- \"captions\": an array with one string for each panel, in order. Each caption has 1 to 3 short sentences in plain English, in the present tense.
- \"sfx\": an array with one string for each panel: one word of sound for the main event (\"PLOP!\"), or \"\" for no sound.

Rules for a caption. They are checked by a program, and a caption that breaks one is thrown away.
1. Say only what the panel's facts say: its events, the fluents that start and end, what was refused, what holds.
2. Use a name of the program only if the facts of that panel have it. Write each name as the program writes it.
3. Use a number only if the facts of that panel have it. Do not give cycle numbers or line numbers.
4. No speech and no quotation marks: nobody says anything in a caption.
5. No praise and no drama. A reader with no training in computing must understand each sentence.
6. Each caption has at most 220 characters.", [FigList, Latent]).

user_prompt(Board, Clauses, _Actors, U) :-
	findall(_{n: I, cycles: Cy, facts: F},
		( nth1(I, Board.panels, P), panel_facts(P, Cy, F) ),
		Panels),
	findall(_{id: Id, kind: Kind, text: Text, acted_times: Acted},
		( member(L, Board.latent), latent_text(L, Clauses, Text),
		  get_dict(id, L, Id), get_dict(kind, L, Kind), get_dict(acted, L, Acted) ),
		Latent),
	D = _{names: Board.names, latent_actors: Latent, panels: Panels,
	      outcome: Board.outcome},
	with_output_to(string(J), json_write_dict(current_output, D, [width(100)])),
	length(Panels, N),
	format(string(U), "The run, in ~w panels:~n~w~nWrite the JSON object. \"captions\" and \"sfx\" have ~w entries each.", [N, J, N]).

panel_facts(P, Cy, F) :-
	format(string(Cy), "~w to ~w", [P.from, P.to]),
	(   P.kind == "beat"
	->  findall(_{event: ET, by: EK, starts: St, ends: En},
		    ( member(E, P.events), get_dict(text, E, ET), get_dict(kind, E, EK),
		      get_dict(changes, E, Chs),
		      findall(CT, ( member(C, Chs), get_dict(kind, C, CK), CK \== "terminated", get_dict(text, C, CT) ), St),
		      findall(CT, ( member(C, Chs), get_dict(kind, C, "terminated"), get_dict(text, C, CT) ), En) ),
		    Es),
	    findall(_{refused: RT, because_also: RE, because_state: RS},
		    ( member(R, P.refusals), get_dict(text, R, RT),
		      get_dict(with_events, R, RE), get_dict(with_state, R, RS) ), Rs),
	    F = _{kind: "something happens", events: Es, refused_by_a_constraint: Rs}
	;   P.kind == "start"
	->  F = _{kind: "the start", holds: P.holds}
	;   P.kind == "end"
	->  F = _{kind: "the end of the run", holds: P.holds, outcome: P.outcome}
	;   findall(T, ( member(I, P.items), silence_text(I, T) ), Ts),
	    F = _{kind: "what did not happen", items: Ts}
	).

silence_text(I, T) :-
	(   I.what == "fluent" -> format(string(T), "nothing ends this fluent: ~w", [I.text])
	;   I.what == "rule" -> T = "a rule of the program never fired"
	;   T = "a constraint of the program never refused anything"
	).

latent_text(L, Clauses, Text) :-
	(   get_dict(line, L, Line), integer(Line),
	    atom_number(K, Line), get_dict(K, Clauses, T0), string(T0)
	->  Text = T0
	;   L.kind == "law" -> Text = "the causal laws: they start and end the fluents"
	;   Text = ""
	).

repair_prompt(Faults, R) :-
	findall(S, ( member(fault(I, Why), Faults),
		     format(string(S), "- caption ~w: ~w", [I, Why]) ), Ss),
	atomic_list_concat(Ss, '\n', A),
	format(string(R), "These captions broke the rules:~n~w~nAnswer with the whole JSON object again, with those captions written again from the facts of their panels.", [A]).

%	What of the model's answer can be used, and what is wrong with the rest.
checked(Board, D, Words, Faults) :-
	length(Board.panels, N),
	( get_dict(title, D, T0), string(T0), string_length(T0, TL), TL =< 60 -> Title = T0 ; Title = null ),
	story_figures(Figs),
	(   get_dict(cast, D, C0), is_dict(C0)
	->  findall(Name-_{fig: FS},
		    ( member(NameD, Board.names), atom_string(Name, NameD.name),
		      get_dict(Name, C0, V), is_dict(V), get_dict(fig, V, FS0),
		      atom_string(F, FS0), memberchk(F, Figs), atom_string(F, FS) ),
		    CastPairs),
	    dict_pairs(Cast, story, CastPairs)
	;   Cast = story{}
	),
	(   get_dict(latent, D, L0), is_dict(L0)
	->  findall(Id-NameS,
		    ( member(L, Board.latent), atom_string(Id, L.id),
		      get_dict(Id, L0, NameS), string(NameS),
		      string_length(NameS, Len), Len > 0, Len =< 32 ),
		    LatentPairs),
	    dict_pairs(Latent, story, LatentPairs)
	;   Latent = story{}
	),
	( get_dict(captions, D, Caps0), is_list(Caps0) -> true ; Caps0 = [] ),
	( get_dict(sfx, D, Sfx0), is_list(Sfx0) -> true ; Sfx0 = [] ),
	numlist(1, N, Is),
	maplist(caption_checked(Board, Caps0), Is, Caps, FaultLists),
	append(FaultLists, Faults),
	maplist(sfx_checked(Sfx0), Is, Sfx),
	Words = _{title: Title, cast: Cast, latent: Latent, captions: Caps, sfx: Sfx}.

sfx_checked(Sfx0, I, S) :-
	(   nth1(I, Sfx0, S0), string(S0), string_length(S0, L), L =< 14,
	    \+ sub_string(S0, _, _, _, " ")
	->  S = S0
	;   S = ""
	).

caption_checked(Board, Caps0, I, Cap, Faults) :-
	nth1(I, Board.panels, Panel),
	(   nth1(I, Caps0, C), string(C)
	->  (   caption_fault(Board, Panel, C, Why)
	    ->	Cap = null, Faults = [fault(I, Why)]
	    ;	Cap = C, Faults = []
	    )
	;   Cap = null, Faults = [fault(I, "there is no caption for this panel")]
	).

%	The first thing wrong with a caption, if anything is.
caption_fault(_, _, C, Why) :-
	string_length(C, L), L > 260, !,
	Why = "it is longer than 220 characters".
caption_fault(_, _, C, Why) :-
	( sub_string(C, _, _, _, "\"") ; sub_string(C, _, _, _, "“") ), !,
	Why = "it has quotation marks: nobody speaks in a caption".
caption_fault(_, Panel, C, Why) :-
	panel_text(Panel, Text),
	numbers_in(C, CNs), numbers_in(Text, PNs),
	member(X, CNs), \+ memberchk(X, PNs), !,
	format(string(Why), "it has the number ~w, which the facts of the panel do not have", [X]).
caption_fault(Board, Panel, C, Why) :-
	panel_text(Panel, Text),
	words_in(C, CWs), words_in(Text, PWs),
	member(NameD, Board.names), string_lower(NameD.name, Name),
	string_length(Name, NL), NL > 1,
	memberchk(Name, CWs), \+ memberchk(Name, PWs), !,
	format(string(Why), "it has the name ~w, which the facts of the panel do not have", [NameD.name]).

%	All the text of a panel's facts, for the check.
panel_text(P, Text) :-
	findall(S, panel_string(P, S), Ss),
	atomic_list_concat(Ss, ' ', A), atom_string(A, Text).

panel_string(P, S) :- get_dict(holds, P, Hs), member(S, Hs).
panel_string(P, S) :- get_dict(outcome, P, S).
panel_string(P, S) :- get_dict(items, P, Is), member(I, Is), ( get_dict(text, I, S) ; get_dict(term, I, S) ).
panel_string(P, S) :-
	get_dict(events, P, Es), member(E, Es),
	(   S = E.text ; S = E.term
	;   member(C, E.changes), ( S = C.text ; S = C.fluent )
	).
panel_string(P, S) :-
	get_dict(refusals, P, Rs), member(R, Rs),
	( S = R.text ; S = R.term ; member(S, R.with_events) ; member(S, R.with_state) ).
panel_string(P, S) :- get_dict(composites, P, Cs), member(C, Cs), ( S = C.text ; S = C.term ).

numbers_in(Text, Ns) :-
	split_string(Text, " ,;:.()[]!?'’—-/\n\t", "", Parts),
	findall(P, ( member(P, Parts), P \== "", catch(number_string(_, P), _, fail) ), Ns).

%	The words of a text, in small letters. A name of a program can have an
%	underscore or a digit in it (`fork1`), and is one word.
words_in(Text, Ws) :-
	string_lower(Text, Low),
	string_codes(Low, Cs),
	maplist([C, D]>>( ( code_type(C, alnum) ; C =:= 0'_ ) -> D = C ; D = 0'  ), Cs, Ds),
	string_codes(Clean, Ds),
	split_string(Clean, " ", "", Ws0),
	exclude(==(""), Ws0, Ws).

%	The second answer where it is good, the first where the second is not.
merge_words(W1, W2, W) :-
	( W2.title \== null -> T = W2.title ; T = W1.title ),
	( W2.cast \== story{} -> Cast = W2.cast ; Cast = W1.cast ),
	( W2.latent \== story{} -> Latent = W2.latent ; Latent = W1.latent ),
	maplist([A, B, C]>>( B \== null -> C = B ; C = A ), W1.captions, W2.captions, Caps),
	maplist([A, B, C]>>( B \== "" -> C = B ; C = A ), W1.sfx, W2.sfx, Sfx),
	W = _{title: T, cast: Cast, latent: Latent, captions: Caps, sfx: Sfx}.
