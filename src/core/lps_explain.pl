/* lps_explain.pl — explanations, the timeline, and the state-change diagram
   (§I.10.2, §I.10.3, §I.10.5).

   §I.10.5 is blunt about why the old `why/1` was not enough:

   > It is weak in three ways: it explains fluents but not *actions*; it cannot
   > explain *absence*; and it has no notion of the reactive rule that drove
   > everything.

   All three are addressed by reading the derivation forest the engine now
   records unconditionally — action ancestry, rule firings, state changes with
   the causal law responsible, denials that blocked an action, prospective
   constraints that rejected a state. Nothing here re-runs the program or
   re-derives anything: an explanation is a *reading of the trace*, which is
   what makes it trustworthy. If the engine did not record it, this module says
   so rather than guessing.

   The five question forms of §I.10.5:

   Two diagrams over the same trace, and they are not the same diagram:

     lps_state_changes/4  what changed BETWEEN two adjacent cycles
     lps_automaton/4      the run as a finite automaton — every DISTINCT state
			  once, however often it recurs, with the events that
			  move between them

   The second is upstream's `godfa/1`. See its own section below for why
   collapsing recurring states is the whole point of it.

     why(happened(A), T)      the rule/goal chain that produced the action
     why(holds(F), T)         last initiating event, or the intensional
			      derivation, or persistence since T'
     why(stopped(F), T)       the terminating event and its cause
     why_not(happened(A), T)  the hard one — four answerable cases, and an
			      honest "no applicable rule" outside them
     what_if(Events, T)       fork, replay, diff (lives in lps_session.pl,
			      which owns forking; trace_diff/3 is here)

   Explanations are trees of `node(Label, Detail, Children)`. §I.10.5 asks for
   LE2's explanation-tree node format so the same component renders both; that
   repository is not available here, so this is a plain label/detail/children
   tree with the same shape, and mapping it to LE2's field names is a
   rendering concern rather than a structural one.
*/

:- module(lps_explain, [
	lps_explain/4,           % +Program, +Trace, +Question, -Explanation
	lps_timeline/3,          % +Program, +Trace, -Timeline
	lps_state_changes/4,     % +Program, +Trace, +Cycle, -Changes
	trace_diff/3,            % +TraceA, +TraceB, -Diff
	explanation_text/2,      % +Explanation, -Lines
	trace_cycles/2,          % +Trace, -MaxCycle
	trace_stage/4,           % +Trace, +Stage, ?Cycle, -Items
	lps_display_scene/4,     % +Program, +Trace, +Cycle, -Scene
	lps_display_scene/5,     % +Program, +Trace, +Cycle, +Declaration, -Scene
	lps_automaton/4,         % +Program, +Trace, +Options, -Automaton
	lps_scene_focus/3        % +Program, +Trace, -Focus
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(terms), [variant/2]).
:- use_module(lps_ops).
:- use_module(lps_program).
:- use_module(lps_store).

:- discontiguous answer/5.

		 /*******************************
		 *	  trace accessors	*
		 *******************************/

trace_stage(Trace, Stage, Cycle, Items) :-
	member(stage(Stage, Cycle, Items), Trace).

trace_cycles(Trace, Max) :-
	findall(C, member(stage(_, C, _), Trace), Cs),
	( Cs == [] -> Max = 0 ; max_list(Cs, Max) ).

%	Records are deduplicated on the way out rather than on the way in: a
%	phase-10 retry re-runs the state update and re-records, and the engine
%	should not pay to be exact about something only a reader cares about.
uniq(L, U) :- uniq_(L, [], U).
uniq_([], _, []).
uniq_([X|Xs], Seen, Out) :-
	(   member(S, Seen), variant(S, X)
	->  Out = Out1, Seen1 = Seen
	;   Out = [X|Out1], Seen1 = [X|Seen]
	),
	uniq_(Xs, Seen1, Out1).

		 /*******************************
		 *	   explanations		*
		 *******************************/

%!	lps_explain(+Program, +Trace, +Question, -Explanation) is det.
%
%	Explanation = explanation(Question, Verdict, Tree).
lps_explain(P, Trace, Question, explanation(Question, Verdict, Tree)) :-
	(   answer(Question, P, Trace, Verdict, Tree)
	->  true
	;   Verdict = unknown,
	    Tree = node('no answer', 'the question form is not recognised', [])
	).

%	E was among the program's observations for the cycle ending at T.
observed(P, E, T) :-
	catch(p_observe(P, Evs, T), _, fail),
	member(E0, Evs), E0 =@= E, !.

% ---- why did action A happen at T? ----
answer(why(happened(A), T), P, Trace, Verdict, Tree) :- !,
	(   occurred(Trace, A, T, Actual)
	->  Verdict = happened,
	    Cycle is T - 1,
	    format(atom(L), '~q occurred from cycle ~w to ~w', [Actual, Cycle, T]),
	    ancestry_nodes(P, Trace, Cycle, Actual, Kids),
	    (   observed(P, Actual, T)
	    ->  D = 'observed: an event from outside the program (its scenario), which no integrity constraint refused'
	    ;   D = 'committed while resolving goals in the previous cycle'
	    ),
	    Tree = node(L, D, Kids)
	;   Verdict = did_not_happen,
	    format(atom(L), '~q did not occur at cycle ~w', [A, T]),
	    answer(why_not(happened(A), T), P, Trace, _, Sub),
	    Tree = node(L, 'see instead why it did not', [Sub])
	).

% ---- why does fluent F hold at T? ----
answer(why(holds(F), T), P, Trace, Verdict, Tree) :- !,
	(   holds_at(Trace, F, T, Actual)
	->  Verdict = holds,
	    format(atom(L), '~q holds at cycle ~w', [Actual, T]),
	    holds_because(P, Trace, Actual, T, Kids),
	    Tree = node(L, '', Kids)
	;   holds_by_default(P, Trace, F, T, Actual)
	->  Verdict = holds_by_default,
	    format(atom(L), '~q holds at cycle ~w', [Actual, T]),
	    Tree = node(L, '(the default: no entry was stored)', [])
	;   Verdict = does_not_hold,
	    format(atom(L), '~q does not hold at cycle ~w', [F, T]),
	    Tree = node(L, 'it is not among the state fluents recorded for that cycle', [])
	).

% ---- why did F stop holding? ----
answer(why(stopped(F), T), P, Trace, Verdict, Tree) :- !,
	(   last_change(Trace, stopped, F, T, C, Fluent, Action, Law, Kind)
	->  Verdict = terminated,
	    format(atom(L), '~q stopped holding at cycle ~w', [Fluent, C]),
	    law_node(P, Kind, Law, LawNode),
	    cause_nodes(P, Trace, C, Action, CauseKids),
	    Tree = node(L, '', [LawNode, node('terminated by', Action, CauseKids)])
	;   holds_at(Trace, F, T, _)
	->  Verdict = still_holds,
	    format(atom(L), '~q still holds at cycle ~w', [F, T]),
	    Tree = node(L, 'nothing terminated it', [])
	;   Verdict = never_held,
	    format(atom(L), '~q is not recorded as having held before cycle ~w', [F, T]),
	    Tree = node(L, 'no terminating event, because it never started', [])
	).

% ---- why did action A NOT happen at T? ----
answer(why_not(happened(A), T), P, Trace, Verdict, Tree) :- !,
	(   occurred(Trace, A, T, Actual)
	->  Verdict = happened,
	    format(atom(L), '~q did occur at cycle ~w', [Actual, T]),
	    Tree = node(L, 'ask why it happened instead', [])
	;   why_not_reasons(P, Trace, A, T, Verdict, Reasons),
	    format(atom(L), '~q did not occur at cycle ~w', [A, T]),
	    Tree = node(L, '', Reasons)
	).

/* ---- why does F NOT hold at T? ----
 *
 * The counterfactual about *state*, which the pane needs because you cannot
 * click on a fluent that was not drawn. Four answers, and they are as distinct
 * as `why_not(happened(…))`'s four:
 *
 *   it does hold            the question is about something that is true
 *   terminated              it held, and something stopped it — name what
 *   never held              it has never been in the state, and no causal law
 *                           mentions it, so nothing could have put it there
 *   nothing initiated it    a law *could* have, but its cause never happened
 */
answer(why_not(holds(F), T), P, Trace, Verdict, Tree) :- !,
	(   holds_at(Trace, F, T, Actual)
	->  Verdict = holds,
	    format(atom(L), '~q does hold at cycle ~w', [Actual, T]),
	    Tree = node(L, 'ask why it holds instead', [])
	;   last_change(Trace, stopped, F, T, C, Fluent, Action, Law, Kind)
	->  Verdict = terminated,
	    format(atom(L), '~q held, and stopped at cycle ~w', [Fluent, C]),
	    law_node(P, Kind, Law, LawNode),
	    cause_nodes(P, Trace, C, Action, CauseKids),
	    Tree = node(L, '', [LawNode, node('terminated by', Action, CauseKids)])
	;   Verdict = never_held,
	    format(atom(L), '~q is not in the state at cycle ~w and never has been', [F, T]),
	    could_start_nodes(P, F, Kids),
	    Tree = node(L, '', Kids)
	).

/*  What *could* have put F in the state — the causal laws whose fluent
    unifies with it. Naming them is the useful answer: either there are none,
    and the program has no way to make F true at all, or there are, and the
    question becomes why their cause never happened. */
could_start_nodes(P, F, Nodes) :-
	findall(node(L, D, []),
		( member(Kind, [initiated, updated]),
		  starting_law(P, Kind, F, Src, Term),
		  format(atom(L), 'a ~w law at ~w could put it there', [Kind, Src]),
		  format(atom(D), '~q', [Term]) ),
		Nodes0),
	(   Nodes0 == []
	->  Nodes = [node('no causal law mentions it',
			  'nothing in this program can make it true — check the term, \c
and whether it should have been in `initially`', [])]
	;   append(Nodes0,
		   [node('so the question is why none of their causes happened', '', [])],
		   Nodes)
	).

starting_law(P, initiated, F, Src, Term) :-
	p_clause_src(P, initiated, _, Term, Src),
	Term = initiated(_, Fluent, _),
	\+ Fluent \= F.
starting_law(P, updated, F, Src, Term) :-
	p_clause_src(P, updated, _, Term, Src),
	Term = updated(_, Fluent, Old-New, _),
	%  `updated` records the *values* replaced, so the fluent it produces is
	%  the pattern with New in Old's place.
	copy_term(Fluent-Old-New, F2-O2-N2),
	O2 = N2,
	\+ F2 \= F.

answer(_, _, _, _, _) :- fail.

		 /*******************************
		 *    the four answerable cases	*
		 *******************************/

/* §I.10.5: "Answerable in four cases: no rule instance ever created the goal;
   the goal existed but a denial blocked the action (name the clause); the goal
   existed but a prospective constraint rejected the resulting state (name it);
   under planning mode, no plan was found within the horizon. Otherwise report
   'no applicable rule', honestly."

   The honesty matters more than the coverage. An explanation facility that
   invents a plausible reason is worse than one that admits it does not know,
   because the whole point is to be trusted after an incident.
*/
why_not_reasons(P, Trace, A, T, Verdict, Reasons) :-
	Cycle is T - 1,
	findall(N, refused_node(P, Trace, A, Cycle, N), Refused),
	findall(N, blocked_node(P, Trace, A, Cycle, N), Blocked),
	findall(N, prospective_node(P, Trace, A, Cycle, N), Prospective),
	(   scheduled_elsewhere(Trace, A, Cycle, Node)
	->  Verdict = scheduled_for_another_cycle, Reasons = [Node]
	;   member(no_plan_found(_, Achieve, H), Trace)
	->  Verdict = no_plan_found,
	    format(atom(NL), 'no plan was found within horizon ~w', [H]),
	    format(atom(ND), 'the goal was achieve ~q', [Achieve]),
	    Reasons = [node(NL, ND, [])]
	;   Refused \== []
	->  Verdict = refused_by_constraint, Reasons = Refused
	;   Blocked \== []
	->  Verdict = blocked_by_denial, Reasons = Blocked
	;   Prospective \== []
	->  Verdict = rejected_by_prospective_constraint, Reasons = Prospective
	;   \+ goal_existed(Trace, A)
	->  Verdict = no_goal_created,
	    Reasons = [node('no rule instance ever created a goal for it',
			    'no reactive rule fired with this action in its consequent', [])]
	;   Verdict = no_applicable_rule,
	    Reasons = [node('no applicable rule',
			    'a goal for it existed, but nothing in the trace records it \c
			     being blocked or rejected — the engine simply never had to \c
			     commit it', [])]
	).

%	The commonest honest answer under planning mode: the action is in the
%	plan, just not for this cycle.
scheduled_elsewhere(Trace, A, Cycle, node(L, D, [])) :-
	member(plan_step(C, I, Set, Achieve), Trace),
	C \== Cycle,
	member(X, Set), \+ X \= A, !,
	T is C + 1,
	format(atom(L), 'the plan schedules it for cycle ~w, as step ~w', [T, I]),
	format(atom(D), 'for achieve ~q', [Achieve]).

%	An observed event that an integrity constraint refused: it was made (an
%	observation, a call from outside), and the constraint's conditions held
%	in the state it arrived in, so it did not happen — with its companions of
%	the same cycle, which the engine refuses together.
refused_node(P, Trace, A, Cycle, node(L, D, Kids)) :-
	findall(r(Es, Conds),
		( member(observation_refused(Cycle, Es, Conds), Trace),
		  member(E, Es), \+ E \= A ),
		Rs0),
	uniq(Rs0, Rs),
	member(r(Es, Conds), Rs),
	format(atom(L), 'it was observed and refused: an integrity constraint held in the state it arrived in', []),
	(   Es = [_, _|_]
	->  format(atom(D), 'false ~q (with the other events of the cycle: ~q)', [Conds, Es])
	;   format(atom(D), 'false ~q', [Conds])
	),
	denial_source_nodes(P, Conds, Kids).

blocked_node(P, Trace, A, Cycle, node(L, D, Kids)) :-
	findall(bl(E, Denial),
		( member(action_blocked(Cycle, E, _, _, Denial), Trace), \+ E \= A ),
		Bs0),
	uniq(Bs0, Bs),
	member(bl(E, Denial), Bs),
	format(atom(L), 'a denial blocked ~q', [E]),
	format(atom(D), 'false ~q', [Denial]),
	denial_source_nodes(P, Denial, Kids).

prospective_node(P, Trace, A, Cycle, node(L, D, Kids)) :-
	findall(Conds,
		( member(prospective_violation(Cycle, Conds), Trace),
		  mentions_action(Conds, A) ),
		Cs0),
	uniq(Cs0, Cs),
	member(Conds, Cs),
	L = 'a prospective constraint rejected the state it would have produced',
	format(atom(D), 'false ~q', [Conds]),
	denial_source_nodes(P, Conds, Kids).
%	An invariant — a constraint about the state alone, naming no event —
%	rejects the next state whatever action produced it, so every action
%	chosen in that cycle is put off together. It names no action, so the
%	clause above cannot find it; it is the reason when the action was wanted
%	(a goal for it existed).
prospective_node(P, Trace, A, Cycle, node(L, D, Kids)) :-
	\+ ( member(prospective_violation(Cycle, C0), Trace), mentions_action(C0, A) ),
	goal_existed(Trace, A),
	findall(Conds,
		( member(prospective_violation(Cycle, Conds), Trace),
		  \+ member(happens(_, _, _), Conds) ),
		Cs0),
	uniq(Cs0, Cs),
	member(Conds, Cs),
	L = 'an invariant rejected the state the actions chosen in that cycle would have produced',
	format(atom(D), 'false ~q', [Conds]),
	denial_source_nodes(P, Conds, Kids).

mentions_action(Conds, A) :-
	member(happens(E, _, _), Conds),
	\+ E \= A, !.

goal_existed(Trace, A) :-
	member(rule_fired(_, _, Consequent), Trace),
	sub_action(Consequent, A), !.

sub_action(C, A) :- is_list(C), !, member(X, C), sub_action(X, A).
sub_action(happens(E, _, _), A) :- !, \+ E \= A.
sub_action((X, Y), A) :- !, ( sub_action(X, A) ; sub_action(Y, A) ).
sub_action(_, _) :- fail.

		 /*******************************
		 *	   derivation chain	*
		 *******************************/

%	committed action → composite events that produced it → the reactive-rule
%	instance that created the goal → the rule in the source.
ancestry_nodes(P, Trace, Cycle, A, Nodes) :-
	findall(anc(E, T1, T2),
		( member(action_ancestor(Cycle, Act, E, T1, T2), Trace), \+ Act \= A ),
		As0),
	uniq(As0, As),
	findall(node(L, D, []),
		( member(anc(E, T1, T2), As),
		  format(atom(L), 'while resolving the composite event ~q', [E]),
		  format(atom(D), 'from ~w to ~w', [T1, T2]) ),
		AncNodes),
	findall(E, member(anc(E, _, _), As), Chain),
	rule_nodes(P, Trace, Cycle, A, Chain, RuleNodes),
	plan_nodes(Trace, Cycle, A, PlanNodes),
	append([AncNodes, RuleNodes, PlanNodes], Nodes).

/* A rule's consequent usually names a *composite event*, not the basic action
   that eventually got committed, so matching the action alone finds nothing.
   Matching against the action's own ancestor chain finds exactly the rule that
   started it. Only when that fails do we fall back to every rule that fired in
   the cycle — and then say so, rather than presenting a guess as a derivation.
*/
rule_nodes(P, Trace, Cycle, A, Chain, Nodes) :-
	findall(rf(Id, C),
		( member(rule_fired(Cycle, Id, C), Trace),
		  ( sub_action(C, A) ; member(E, Chain), sub_action(C, E) ) ),
		Rs0),
	uniq(Rs0, Rs),
	(   Rs \== []
	->  rule_node_list(P, Rs, Nodes)
	;   findall(rf(Id2, C2), member(rule_fired(Cycle, Id2, C2), Trace), All0),
	    uniq(All0, All),
	    (	All == []
	    ->	Nodes = []
	    ;	rule_node_list(P, All, Kids),
		Nodes = [node('goal origin not determined',
			      'no rule consequent mentions this action or its composite \c
			       ancestors; the rules that did fire in this cycle were',
			      Kids)]
	    )
	).

%	Under planning mode the plan is the provenance: no rule fired, no
%	composite event was reduced, the planner simply scheduled it.
plan_nodes(Trace, Cycle, A, Nodes) :-
	findall(node(L, D, []),
		( member(plan_step(Cycle, I, Set, Achieve), Trace),
		  member(X, Set), \+ X \= A,
		  format(atom(L), 'scheduled by the planner as step ~w of the plan', [I]),
		  format(atom(D), 'for achieve ~q', [Achieve]) ),
		Nodes0),
	uniq(Nodes0, Nodes).

rule_node_list(P, Rs, Nodes) :-
	findall(node(L, D, Kids),
		( member(rf(Id, C), Rs),
		  format(atom(L), 'from the goal created by a reactive rule (goal ~w)', [Id]),
		  format(atom(D), 'consequent ~q', [C]),
		  rule_source_nodes(P, C, Kids) ),
		Nodes).

/* The rule is identified by matching the recorded consequent back against the
   program's reactive rules. The alternative — carrying a rule id through
   dc_process — would mean changing the shape of the terms in the working rule
   list, which is the one data structure whose handling selection_spec SP1–SP3
   pin down exactly. Matching after the fact costs nothing and risks nothing,
   and where it is ambiguous it says so.
*/
rule_source_nodes(P, Consequent, Nodes) :-
	findall(Src-Term,
		( p_clause_src(P, reactive_rule, _, Term, Src),
		  Term = reactive_rule(_, RC),
		  \+ RC \= Consequent ),
		Matches),
	(   Matches = [Src-reactive_rule(Ant, _)]
	->  format(atom(L), 'rule at ~w', [Src]),
	    format(atom(D), 'if ~q then ...', [Ant]),
	    Nodes = [node(L, D, [])]
	;   Matches == []
	->  Nodes = [node('rule not identified',
			  'the consequent matches no reactive rule in the program', [])]
	;   length(Matches, N),
	    format(atom(L), '~w candidate rules match this consequent', [N]),
	    findall(node(L2, '', []),
		    ( member(S, Matches), S = Src2-_, format(atom(L2), 'rule at ~w', [Src2]) ),
		    Kids),
	    Nodes = [node(L, 'ambiguous — reported rather than guessed', Kids)]
	).

denial_source_nodes(P, Denial, Nodes) :-
	(   p_clause_src(P, d_pre, _, Term, Src),
	    ( Term = d_pre(Conds) -> true ; Conds = Term ),   % stored as the clause
	    \+ Conds \= Denial
	->  format(atom(L), 'denial at ~w', [Src]),
	    Nodes = [node(L, '', [])]
	;   Nodes = []
	).

law_node(P, Kind, Law, node(L, D, [])) :-
	(   integer(Law),
	    p_clause_src(P, Kind, Law, Term, Src)
	->  format(atom(L), '~w causal law at ~w', [Kind, Src]),
	    format(atom(D), '~q', [Term])
	;   format(atom(L), '~w by an editing action', [Kind]),
	    D = ''
	).

cause_nodes(P, Trace, Cycle, happens(E, _, _), Nodes) :- !,
	T is Cycle + 1,
	(   occurred(Trace, E, T, _)
	->  ancestry_nodes(P, Trace, Cycle, E, Nodes)
	;   Nodes = []
	).
cause_nodes(_, _, _, _, []).

		 /*******************************
		 *	  fluent explanation	*
		 *******************************/

holds_because(P, Trace, F, T, Nodes) :-
	(   last_change(Trace, started, F, T, C, _Fluent, Action, Law, Kind)
	->  law_node(P, Kind, Law, LawNode),
	    ( Kind == updated
	    ->  format(atom(L), 'set at cycle ~w and has persisted since', [C])
	    ;   format(atom(L), 'initiated at cycle ~w and has persisted since', [C]) ),
	    format(atom(D), 'by ~q', [Action]),
	    cause_nodes(P, Trace, C, Action, CauseKids),
	    Nodes = [node(L, D, [LawNode|CauseKids])]
	;   in_initial_state(P, F)
	->  Nodes = [node('in the initial state', 'and nothing has terminated it', [])]
	;   intensional_nodes(P, F, Nodes)
	).

%	An intensional fluent is not in the state at all — it is derived on
%	demand — so the honest answer names the clauses that could derive it
%	rather than inventing a derivation the engine never recorded.
intensional_nodes(P, F, Nodes) :-
	(   p_intensional(P, F)
	->  findall(node(L, D, []),
		    ( p_clause_src(P, l_int, _, l_int(holds(Head, _), Body), Src),
		      \+ Head \= F,
		      format(atom(L), 'derived by an intensional clause at ~w', [Src]),
		      format(atom(D), 'if ~q', [Body]) ),
		    Nodes0),
	    ( Nodes0 == [] -> Nodes = [node('intensional, but no clause matches', '', [])]
	    ; Nodes = Nodes0 )
	;   Nodes = [node('no recorded cause',
			  'it is in the state but the trace records no event that put it \c
			   there — check whether it came from an editing action', [])]
	).

in_initial_state(P, F) :-
	p_initial_state(P, L), member(X, L), \+ X \= F, !.

/*  The most recent change at or before T that *started* or *stopped* F.
 *
 *  Sense, not kind, because `updates … to … in …` is a single record that both
 *  starts and stops something: `state_change(C, updated, Old-New, …)`. Asking
 *  "why does F hold?" against the `initiated` records alone finds nothing in
 *  any program written with `updates` — which is most of them, and which is why
 *  the goat's wolf arrived on the north bank with "no recorded cause". The
 *  record is there; the question was being asked of the wrong half of it.
 */
last_change(Trace, Sense, F, T, C, Fluent, Action, Law, Kind) :-
	findall(c(C0, Fl, A, Law0, K),
		( member(state_change(C0, K, Fl0, A, Law0), Trace),
		  C0 < T,
		  change_fluent(Sense, K, Fl0, Fl),
		  \+ Fl \= F ),
		Cs),
	Cs \== [],
	last_by_cycle(Cs, c(C, Fluent, Action, Law, Kind)).

change_fluent(started, initiated, F, F).
change_fluent(started, updated, _Old-New, New).
change_fluent(stopped, terminated, F, F).
change_fluent(stopped, updated, Old-_New, Old).

last_by_cycle([X], X) :- !.
last_by_cycle([c(C1, F1, A1, L1, K1), c(C2, F2, A2, L2, K2)|R], Best) :-
	(   C2 >= C1
	->  last_by_cycle([c(C2, F2, A2, L2, K2)|R], Best)
	;   last_by_cycle([c(C1, F1, A1, L1, K1)|R], Best)
	).

occurred(Trace, A, T, Actual) :-
	trace_stage(Trace, events, T, Items),
	member(Actual, Items),
	\+ Actual \= A, !.

%	A fluent declared with a default (defaults/1) holds it for a bound key
%	with no stored entry at T: the state records no fact, and the answer is
%	the declaration.
holds_by_default(P, Trace, F, T, Actual) :-
	p_fluent_default(P, F, Key, D),
	Key =.. [_|As], append(Ks, [_], As), ground(Ks),
	\+ holds_at(Trace, Key, T, _),
	copy_term(F, Actual), functor(Actual, _, N), arg(N, Actual, V), V = D.

holds_at(Trace, F, T, Actual) :-
	trace_stage(Trace, fluents, T, Items),
	member(Actual, Items),
	\+ Actual \= F, !.

		 /*******************************
		 *	    the timeline	*
		 *******************************/

/* §I.10.2. The `.lpst` structure is already a timeline — stage × cycle ×
   items — so this is a regrouping, not an instrumentation. One lane per
   fluent carrying the intervals over which it holds, one lane for events, one
   for composites, and the cycle range for the cursor.
*/
lps_timeline(_P, Trace, timeline(MaxCycle, FluentLanes, EventLane, CompositeLane)) :-
	trace_cycles(Trace, MaxCycle),
	fluent_lanes(Trace, MaxCycle, FluentLanes),
	stage_lane(Trace, events, MaxCycle, EventLane),
	stage_lane(Trace, composites, MaxCycle, CompositeLane).

fluent_lanes(Trace, Max, Lanes) :-
	findall(F, ( trace_stage(Trace, fluents, _, Items), member(F, Items) ), All),
	uniq(All, Distinct),
	msort(Distinct, Sorted),
	findall(lane(F, Intervals),
		( member(F, Sorted), fluent_intervals(Trace, F, Max, Intervals) ),
		Lanes).

fluent_intervals(Trace, F, Max, Intervals) :-
	findall(C, ( between(0, Max, C), holds_at(Trace, F, C, _) ), Cycles),
	runs(Cycles, Intervals).

%	Maximal runs of consecutive cycles: an interval, not a scatter of points,
%	is what makes a timeline readable.
runs([], []).
runs([C|Cs], [interval(C, End)|Rest]) :-
	run_end(C, Cs, End, Tail),
	runs(Tail, Rest).

run_end(C, [D|Ds], End, Tail) :- D =:= C + 1, !, run_end(D, Ds, End, Tail).
run_end(C, Tail, C, Tail).

stage_lane(Trace, Stage, Max, lane(Stage, Cells)) :-
	findall(cell(C, Items),
		( between(0, Max, C), trace_stage(Trace, Stage, C, Items), Items \== [] ),
		Cells).

		 /*******************************
		 *   the state-change diagram	*
		 *******************************/

/* §I.10.3: per cycle, what was initiated, what terminated, what persisted, and
   which causal law fired for each change. The last part is the one the old
   system most conspicuously lacked, and it is nearly free now that the trace
   carries the law index.
*/
lps_state_changes(P, Trace, Cycle, changes(Cycle, Initiated, Terminated, Updated, Persisted)) :-
	Prev is Cycle - 1,
	changes_of(P, Trace, Prev, initiated, Initiated),
	changes_of(P, Trace, Prev, terminated, Terminated),
	changes_of(P, Trace, Prev, updated, Updated),
	(   trace_stage(Trace, fluents, Cycle, Now),
	    trace_stage(Trace, fluents, Prev, Before)
	->  include(held_before(Before), Now, Persisted)
	;   Persisted = []
	).

held_before(Before, F) :- member(G, Before), variant(F, G), !.

changes_of(P, Trace, Cycle, Kind, Changes) :-
	findall(ch(F, A, Law), member(state_change(Cycle, Kind, F, A, Law), Trace), Cs0),
	uniq(Cs0, Cs),
	findall(change(F, A, Src, Term),
		( member(ch(F, A, Law), Cs), law_src(P, Kind, Law, Src, Term) ),
		Changes).

law_src(P, Kind, Law, Src, Term) :-
	(   integer(Law), p_clause_src(P, Kind, Law, Term, Src)
	->  true
	;   Src = editing_action, Term = Law
	).

		 /*******************************
		 *   the visual mapping (M10)	*
		 *******************************/

/* §I.10.4. `display/2` already exists in the corpus — ten programs declare
   one — and the plan names it as the natural hook, so the visual mapping is
   not a new language feature but a reading of one the programs already have:

     display(location(P,L), [type:ellipse, label:P, point:[PX,PY], ...]) :-
	     locationXY(L,X,Y), PY is Y+10, ...

   A scene is the set of `display/2` answers for the fluents and events of one
   cycle, plus the `display(timeless, _)` backdrop. Scrubbing is then just
   asking for a different cycle, and interpolation between two scenes is the
   front end's business.

   The clause bodies may query the state, so the store is pointed at that
   cycle's fluents and put back afterwards — the same borrow-and-restore the
   planner does when it evaluates a hypothetical state.
*/
lps_display_scene(P, Trace, Cycle, Scene) :-
	lps_display_scene(P, Trace, Cycle, display, Scene).

%!	lps_display_scene(+P, +Trace, +Cycle, +Decl, -Scene) is det.
%
%	Decl is `display` (the 2D mapping, §I.10.4a) or `display3d` (the 3D one,
%	§I.10.4b). Two declarations rather than one reinterpreted: 2D props do not
%	carry into three dimensions without lying about what the author meant, and
%	a program may reasonably want both at once, showing different things.
lps_display_scene(P, Trace, Cycle, Decl, scene(Cycle, Timeless, Items)) :-
	( trace_stage(Trace, fluents, Cycle, Fluents) -> true ; Fluents = [] ),
	( trace_stage(Trace, events, Cycle, Events) -> true ; Events = [] ),
	composites_begun(Trace, Cycle, Composites),
	%  A program with no display/2 clauses has an empty scene, not a failed
	%  one: "this program declares no visual mapping" is an answer the UI can
	%  render, and a failure is not.
	with_borrowed_state(Fluents, Cycle,
			    ( ( display_of(P, Decl, timeless, TL) -> Timeless = TL ; Timeless = [] ),
			      subject_visuals(P, Decl, Fluents, fluent, FV),
			      subject_visuals(P, Decl, Events, event, EV),
			      subject_visuals(P, Decl, Composites, composite, CV),
			      append([FV, EV, CV], Items) )).

/* The composite events that have BEGUN by this cycle, each as the engine
   recorded it: `happens(Event, Start, End)`, carrying its own interval
   (AnimationPlan.md §6).

   A composite is an *act* — a span with a beginning and an end — and that is
   the one narrative shape the corpus can state and the picture could not
   draw. It is offered to `display/2` as a subject in its own right, so a
   clause can put it on the screen as a bar whose extent is computed from its
   own `Start` and `End`:

     display(happens(load(Truck), S, E), [type:rectangle,
	     from:[X0, 0], to:[X1, 12], …]) :- X0 is S * 24, X1 is E * 24.

   `begun`, not `in progress`: an act that is over still belongs in the
   picture, because a reader at cycle 9 wants to see the three acts that got
   the run there, not an empty lane. What that produces is a Gantt chart of
   the run so far, which is what "draw a composite as one bar over its
   sub-events" means in a scene.
*/
composites_begun(Trace, Cycle, Composites) :-
	findall(H,
		( trace_stage(Trace, composites, _, Items),
		  member(H, Items),
		  H = happens(_, Start, _),
		  integer(Start), Start =< Cycle ),
		All),
	uniq(All, Composites).

with_borrowed_state(Fluents, Cycle, Goal) :-
	st_state_list(Old), st_now(OldNow),
	setup_call_cleanup(( st_set_state(Fluents), st_set_now(Cycle) ),
			   once(Goal),
			   ( st_set_state(Old), st_set_now(OldNow) )).

%	Upstream draws only the FIRST display/2 solution for a subject
%	(2dWord.md: "only the first display specification found ... is
%	considered"). The M10 pane drew them all, which is a difference nobody
%	asked for; once/1 restores it.
subject_visuals(P, Decl, Subjects, Kind, Visuals) :-
	findall(visual(Kind, S, Props),
		( member(S, Subjects), once(display_of(P, Decl, S, Props)) ),
		Visuals).

display_of(P, Decl, Subject, Props) :-
	prog_module(P, M),
	Goal =.. [Decl, Subject, Props],
	catch(M:Goal, _, fail),
	is_list(Props).

		 /*******************************
		 *	    trace diff		*
		 *******************************/

%!	trace_diff(+TraceA, +TraceB, -Diff) is det.
%
%	The "what would have happened if…?" payload: two traces, compared the way
%	the conformance contract compares them (stage/cycle keys, membership up
%	to variance) so that a hypothetical reads in the same terms as a test
%	failure.
trace_diff(A, B, diff(Only_A, Only_B)) :-
	findall(only(S, C, Items),
		( trace_stage(A, S, C, IA),
		  ( trace_stage(B, S, C, IB) -> true ; IB = [] ),
		  subtract_variant(IA, IB, Items), Items \== [] ),
		Only_A),
	findall(only(S, C, Items),
		( trace_stage(B, S, C, IB2),
		  ( trace_stage(A, S, C, IA2) -> true ; IA2 = [] ),
		  subtract_variant(IB2, IA2, Items), Items \== [] ),
		Only_B).

subtract_variant([], _, []).
subtract_variant([X|Xs], Ys, Out) :-
	(   member(Y, Ys), variant(X, Y)
	->  Out = Out1
	;   Out = [X|Out1]
	),
	subtract_variant(Xs, Ys, Out1).

		 /*******************************
		 *	    rendering		*
		 *******************************/

%!	explanation_text(+Explanation, -Lines) is det.
%
%	A plain-text rendering, for the CLI and for tests. The tree is the API;
%	this is one view of it.
explanation_text(explanation(_, Verdict, Tree), [Head|Lines]) :-
	format(atom(Head), '[~w]', [Verdict]),
	node_lines(Tree, 0, Lines).

node_lines(node(Label, Detail, Kids), Indent, [Line|Rest]) :-
	Pad is Indent * 2,
	(   Detail == ''
	->  format(atom(Line), '~*c~w', [Pad, 0' , Label])
	;   format(atom(Line), '~*c~w — ~w', [Pad, 0' , Label, Detail])
	),
	I1 is Indent + 1,
	findall(Ls, ( member(K, Kids), node_lines(K, I1, Ls) ), Nested),
	append(Nested, Rest).


		 /*******************************
		 *   the state-transitions       *
		 *   automaton (godfa/1)         *
		 *******************************/

/* The run as a deterministic finite automaton: states are the DISTINCT sets of
   fluents the run passed through, and transitions are the events and actions
   that moved between them.

   This is a different diagram from lps_state_changes/4, and the difference is
   the point. The state-change diagram is per cycle: it answers "what happened
   at cycle 7". The automaton is per *state*: a state the run visits at cycles
   3, 9 and 14 is ONE node with three incoming and three outgoing edges, so a
   loop in the program shows up as a loop on the page. That is what makes
   `bankTransfer` — where two accounts pass ten between them forever — legible
   as a cycle rather than as a strip of eleven near-identical frames.

   Faithful to upstream's dfa_graph/4 (legacy_lps1/utils/visualizer.P) in the
   four decisions that matter:

     - cycle 0 is dropped. Upstream calls this "a hack to discard irrelevant
       state information", and it is: the initial emission at time 0 is the
       program's `initially`, before any rule has run, and including it puts a
       phantom state and a phantom transition at the head of every diagram.
     - a cycle with no fluents at all is still a state — the EMPTY state — so
       that a run which empties the store does not silently lose a node.
     - a node is identified by the SET of cycles it was visited at, which is
       what makes two visits to the same state one node.
     - the initial state is marked, and events and actions are distinguished:
       upstream colours events orange and actions green, and the two mean
       different things (something happened TO the program, versus the program
       DID something).

   Two options, also upstream's:

     abstract_numbers  every number becomes the atom `n`. A program whose state
		       differs only in an amount collapses to a diagram about
		       its shape rather than its arithmetic — which for
		       bankTransfer is the difference between six nodes and
		       sixty.
     non_reflexive     drop transitions that do not change the state. Useful
		       when polled events fire every cycle and would otherwise
		       bury the real transitions in self-loops.
*/

%!	lps_automaton(+Program, +Trace, +Options, -Automaton) is det.
%
%	Automaton is `automaton(Nodes, Edges)` with
%
%	    node(Id, Fluents, Cycles, Initial)   Initial ∈ {true,false}
%	    edge(FromId, ToId, Label, Kind)      Kind ∈ {event,action}
%
%	Id is the node's list of cycles, which is its identity.
lps_automaton(P, Trace, Options, automaton(Nodes, Edges)) :-
	( memberchk(abstract_numbers, Options) -> AN = true ; AN = false ),
	( memberchk(non_reflexive, Options) -> NR = true ; NR = false ),
	state_history(Trace, AN, History),
	(   History == []
	->  Nodes = [], Edges = []
	;   History = [First-_|_],
	    last(History, Last-_),
	    fill_empty(History, First, Last, Full),
	    abstract_states(Full, States),
	    findall(node(Cycles, Fluents, Cycles, Initial),
		    ( member(Fluents-Cycles, States),
		      ( memberchk(First, Cycles) -> Initial = true ; Initial = false ) ),
		    Nodes),
	    automaton_edges(P, Trace, States, AN, NR, Edges)
	).

%	The state at each cycle: a sorted set of fluents, cycle 0 excluded.
state_history(Trace, AN, History) :-
	findall(Cycle-State,
		( trace_stage(Trace, fluents, Cycle, Items),
		  Cycle \== 0,
		  maplist(abstract_if(AN), Items, Items1),
		  sort(Items1, State) ),
		History0),
	keysort(History0, History1),
	uniq(History1, History).

abstract_if(false, X, X) :- !.
abstract_if(true, X, Y) :- abstract_numbers(X, Y).

%	Numbers to `n`, everywhere in the term.
abstract_numbers(X, n) :- number(X), !.
abstract_numbers(X, X) :- var(X), !.
abstract_numbers(X, X) :- atomic(X), !.
abstract_numbers(T, T1) :-
	T =.. [F|Args],
	maplist(abstract_numbers, Args, Args1),
	T1 =.. [F|Args1].

fill_empty(History, First, Last, Full) :-
	findall(C-[],
		( between(First, Last, C), \+ memberchk(C-_, History) ),
		Empty),
	append(History, Empty, Full0),
	keysort(Full0, Full).

%	One entry per DISTINCT state, carrying every cycle it was seen at.
abstract_states(Full, States) :-
	findall(State, member(_-State, Full), All),
	uniq(All, Distinct),
	findall(State-Cycles,
		( member(State, Distinct),
		  findall(C, ( member(C-S, Full), S == State ), Cycles0),
		  sort(Cycles0, Cycles) ),
		States).

%	One edge per (source state, target state, label): an event seen at time
%	T2 moves the run from the state at T2-1 to the state at T2.
automaton_edges(P, Trace, States, AN, NR, Edges) :-
	findall(edge(From, To, Label, Kind),
		( trace_stage(Trace, events, T2, Items),
		  member(Ev, Items),
		  T1 is T2 - 1,
		  T1 \== 0,
		  state_of(States, T1, From),
		  state_of(States, T2, To),
		  ( NR == true -> From \== To ; true ),
		  event_kind(P, Trace, Ev, T2, Kind),
		  abstract_if(AN, Ev, Label) ),
		Edges0),
	uniq(Edges0, Edges).

state_of(States, T, Cycles) :-
	member(_-Cycles, States), memberchk(T, Cycles), !.

%	Upstream's rule, and its reason: an occurrence that is BOTH a declared
%	action and an observed event is an event — the observation is evidence
%	that it happened TO the program rather than being chosen by it.
event_kind(P, Trace, Ev, T2, Kind) :-
	(   p_action(P, Ev),
	    \+ observed_at(P, Trace, Ev, T2)
	->  Kind = action
	;   Kind = event
	).

observed_at(P, _Trace, Ev, T2) :-
	p_observe(P, Events, T2),
	member(E, Events),
	variant(E, Ev), !.

		 /*******************************
		 *	 what is worth showing	*
		 *******************************/

/* The automaton, read as advice to whoever is drawing a picture of the run
   (docs/project/plans/AnimationPlan.md §5).

   Three questions a scene planner has and the trace answers exactly, so that
   nobody has to guess at them and no language model has to be asked:

     * **which fluents discriminate.** A fluent that has the same truth value
       in every state the run passed through contributes nothing to the
       diagram and nothing to the picture: it is backdrop, by construction.
       One that separates two states is the plot. This is the sharp form of
       "what changes": a set difference over the states.
     * **which cycles are worth a frame.** The states are the frames, not the
       cycles: a run of forty cycles through six states wants six pictures, at
       the cycles where the state became something else. Everything between two
       keyframes is the same picture drawn again.
     * **where the run comes back.** A state visited at several cycles is a
       loop, and a reader wants that marked — it is the difference between a
       story and a strip of near-identical frames.

   One deliberate difference from `lps_automaton/4`: cycle 0 is kept. The
   automaton drops it because a node for the state before any rule has run is
   a phantom in a diagram *of the rules*; a picture of the run, on the other
   hand, opens on `initially`, and dropping it loses the one frame that says
   where everything started.
*/

%!	lps_scene_focus(+Program, +Trace, -Focus) is det.
%
%	Focus is focus(Discriminating, Keyframes, Loops):
%
%	  * Discriminating: `disc(Name/Arity, Example, Instances, Kind)` per
%	    fluent that is not simply true (or simply absent) throughout, with
%	    one instance of it to name it by, how many of its instances
%	    discriminate, and `derived` for an intensional fluent, `stored`
%	    otherwise.
%	  * Keyframes: `kf(Cycle, StateId, Events)` in cycle order — the first
%	    recorded cycle, and then every cycle whose state differs from the
%	    cycle before it, with the events recorded at that cycle (what moved
%	    the story on). StateId is the list of cycles that state holds at,
%	    which is the automaton's node identity: a keyframe whose StateId has
%	    more than one member is a state the run returns to.
%	  * Loops: those StateIds, once each.
lps_scene_focus(P, Trace, focus(Disc, Keyframes, Loops)) :-
	focus_history(Trace, History),
	discriminating_fluents(P, History, Disc),
	state_ids(History, Ids),
	findall(kf(C, Id, Evs),
		( member(C-S, History),
		  keyframe_cycle(History, C, S),
		  ( memberchk(S0-Id, Ids), S0 == S -> true ; Id = [C] ),
		  ( trace_stage(Trace, events, C, Evs) -> true ; Evs = [] ) ),
		Keyframes),
	findall(Cs, ( member(_-Cs, Ids), Cs = [_, _|_] ), Loops).

%	The state at each recorded cycle, cycle 0 included, in cycle order and
%	one entry per cycle.
focus_history(Trace, History) :-
	findall(C-S,
		( trace_stage(Trace, fluents, C, Items), sort(Items, S) ),
		History0),
	keysort(History0, History1),
	uniq_keys(History1, History).

uniq_keys([], []).
uniq_keys([C-S|T], [C-S|Out]) :-
	exclude([C2-_]>>(C2 == C), T, T1),
	uniq_keys(T1, Out).

%	C is the first cycle of the history, or its state is not the state of
%	the cycle recorded before it.
keyframe_cycle(History, C, S) :-
	(   History = [C0-_|_], C0 == C
	->  true
	;   previous_recorded(History, C, S0),
	    S0 \== S
	).

previous_recorded(History, C, S) :-
	findall(C0-S0, ( member(C0-S0, History), C0 < C ), Before),
	Before \== [],
	last(Before, _-S).

%	One entry per DISTINCT state, with every cycle it holds at — the
%	automaton's nodes, over this history.
state_ids(History, Ids) :-
	findall(S, member(_-S, History), All),
	uniq(All, Distinct),
	findall(S-Cycles,
		( member(S, Distinct),
		  findall(C, ( member(C-S2, History), S2 == S ), Cycles0),
		  sort(Cycles0, Cycles) ),
		Ids).

discriminating_fluents(P, History, Disc) :-
	findall(F, ( member(_-S, History), member(F, S) ), All),
	uniq(All, Instances),
	include(discriminates(History), Instances, Moving),
	findall(K-F, ( member(F, Moving), functor(F, N, A), K = N/A ), Keyed),
	keysort(Keyed, Sorted),
	group_pairs_by_key(Sorted, Grouped),
	findall(disc(K, Example, Count, Kind),
		( member(K-Fs, Grouped),
		  length(Fs, Count),
		  Fs = [Example|_],
		  ( catch(p_intensional(P, Example), _, fail) -> Kind = derived ; Kind = stored )
		),
		Disc).

%	F is absent from at least one state: it is not simply true throughout.
discriminates(History, F) :-
	member(_-S, History),
	\+ ( member(G, S), variant(F, G) ), !.
