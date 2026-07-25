/* lps_legacy_syntax.pl — external syntax 1: legacy LPS (§I.4).

   The requirement is blunt: legacy surface syntax is unchanged and stays
   parseable directly by Prolog, as today. So this module re-derives the
   surface→internal translation over the operator table of core/lps_ops.pl,
   producing the §I.3 vocabulary.

   The hard part is not the shapes, it is **time threading**. A surface clause
   mostly leaves time implicit:

	makeLoc(Object, Location) from T1 to T3
	if  loc(Object, L2) at T1, row(L2, Location) from T2 to T3.

   and the translator has to decide, for every literal, which time variable it
   gets and which of them are fused. Three rules do the work:

     - a literal that mentions time explicitly (`at T`, `from T1 to T2`,
       `during [T1,T2]`) keeps its own variables and reports ExplicitTime=true;
     - a literal with no explicit time is *anchored* to the enclosing
       interval — that is what ExplicitTime=false is for;
     - a sequence declared `single` (post-conditions, preconditions, negated
       sequences, intensional-fluent bodies) must span one transition, so its
       untimed literals collapse onto the enclosing interval's endpoints.

   Get this wrong and the program still compiles; it just runs a cycle late,
   or never fires. Which is why M2's gate is a diff against psyntax's own
   generated `_.P` for all 102 corpus programs, rather than a handful of unit
   tests.

   Head *hints* are the other stateful part. Whether a bare literal is a
   fluent or an event is decided by what the file has said about it *so far*,
   so translation is order-dependent and single-pass, exactly as upstream. A
   declaration (`fluents f(_)`) is a stronger hint than a usage (`f(x) at T`)
   and overwrites it.

   Dropped, per the plan's non-goals and the user's decision: the lps.js
   syntax (`<-`, `->`, `<=`) and the .lpsw Wei surface syntax. The corpus's
   .lpsw entries are internal-syntax tests and run through the internal
   reader.
*/

:- module(lps_legacy_syntax, [
	legacy_to_internal/4,    % +Source, +Options, -Terms, -Diags
	legacy_term_to_internal/3, % +SurfaceTerm, -InternalTerm, -Diags
	begin_translation/0,
	end_translation/0
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').
:- use_module('../core/lps_time').

%	Hints accumulated while translating one file. Dynamic rather than
%	threaded because translation is inherently a single stateful pass and
%	this module is not part of the pure core.
:- dynamic head_hint/3.          % Template, Sort, Declared
:- dynamic timeless_ref/1.
:- dynamic current_top_term/1.
:- dynamic translation_origin/1.

begin_translation :-
	retractall(head_hint(_, _, _)),
	retractall(timeless_ref(_)),
	retractall(current_top_term(_)).

end_translation :- true.

%!	legacy_to_internal(+Source, +Options, -Terms, -Diags) is det.
%
%	Source is file(Path) or terms(ListOfTermsOrTPairs). Terms come back as
%	`t(InternalTerm, Line)` pairs, ready for lps_compile_terms/5.
legacy_to_internal(file(Path), Options, Terms, Diags) :- !,
	(   current_predicate(lps_source:lps_read_terms/3)
	->  lps_source:lps_read_terms(Path, Raw, ReadDiags)
	;   Raw = [], ReadDiags = []
	),
	(   ReadDiags == []
	->  legacy_to_internal(terms(Raw), [origin(Path)|Options], Terms, Diags)
	;   Terms = [], Diags = ReadDiags
	).
legacy_to_internal(terms(Raw), Options, Terms, Diags) :-
	( memberchk(origin(File), Options) -> true ; File = buffer ),
	retractall(translation_origin(_)), assertz(translation_origin(File)),
	begin_translation,
	foldl(translate_one, Raw, ok([], []), ok(RevTerms, RevDiags)),
	reverse(RevTerms, Terms),
	reverse(RevDiags, Diags),
	end_translation.

translate_one(Item, ok(Ts, Ds), ok(Ts1, Ds1)) :-
	(   Item = t(Term, Line) -> true ; Term = Item, Line = 0 ),
	set_top_term(Term),
	catch(( s2p(Term, Internal) -> R = ok(Internal) ; R = failed ), E, R = error(E)),
	(   R = ok(I0)
	->  drop_true_body(I0, I),
	    Ts1 = [t(I, Line)|Ts], Ds1 = Ds
	;   Ts1 = Ts,
	    format(atom(M), 'cannot translate ~q: ~q', [Term, R]),
	    ( translation_origin(File) -> true ; File = buffer ),
	    diag(error, untranslatable, src(File, Line, 0, legacy), M, D),
	    Ds1 = [D|Ds]
	).

%!	legacy_term_to_internal(+Surface, -Internal, -Diags) is det.
legacy_term_to_internal(Surface, Internal, Diags) :-
	set_top_term(Surface),
	(   catch(s2p(Surface, Internal), _, fail)
	->  Diags = []
	;   format(atom(M), 'cannot translate: ~q', [Surface]),
	    diag(error, untranslatable, unknown, M, D),
	    Diags = [D]
	).

%	`foo :- true.` and `foo.` are the same clause, and psyntax's writer
%	prints the first as the second. Normalising here keeps the generated
%	internal form identical to upstream's, which is what the M2 gate
%	compares.
drop_true_body((H :- true), H) :- !.
drop_true_body(T, T).

set_top_term(T) :-
	retractall(current_top_term(_)),
	(   var(T) -> assertz(current_top_term(var/(-1)))
	;   functor(T, F, N), assertz(current_top_term(F/N))
	).

		 /*******************************
		 *	  term translation	*
		 *******************************/

%	Order matters throughout: the first matching clause wins, and several
%	shapes are only distinguishable by trying them in this sequence.

%	1-2: terms already in internal syntax, or declarations that pass
%	through unchanged. Hints are still remembered from them — that is what
%	makes `fluents f(_)` earlier in the file affect a bare `f(x)` later.
s2p((H :- B), (H :- B)) :-
	do_not_transform_may_hint(H), !.
s2p(Fact, Fact) :-
	Fact \= (_ :- _),
	do_not_transform_may_hint(Fact), !.

%	3: initially
s2p((initially States), initial_state(StatesList)) :- !,
	comma_to_list(States, StatesList),
	remember_hints(fluent, StatesList).

%	4-5: observations
s2p((observe Obs), observe([O1, O2|On], T2)) :-
	nonvar(Obs), functor(Obs, ',', 2), !,
	s2p_observations(Obs, CT2, [O1, O2|On], T2),
	T2 = CT2, nonvar(T2).
s2p((observe E from _T1 to T2), observe([E], T2)) :- !, remember_event_hint(E).
s2p((observe E to T2), observe([E], T2)) :- !, remember_event_hint(E).
s2p((observe E at T2), observe([E], T2)) :- is_some_time(T2), !, remember_event_hint(E).
s2p((observe E from T1), observe([E], T2)) :- number(T1), !, T2 is T1 + 1, remember_event_hint(E).

%	6-8: declarations
s2p((unserializable A), unserializable(NL)) :- !, s2p((actions A), actions(NL)).
s2p((actions A), actions(NL)) :- nonvar(A), !,
	comma_to_list(A, L), functor_arityze(L, NL), remember_declarations(action, NL).
s2p((events A), events(NL)) :- nonvar(A), !,
	comma_to_list(A, L), functor_arityze(L, NL), remember_declarations(event, NL).
s2p((prolog_events A), prolog_events(NL)) :- nonvar(A), !,
	comma_to_list(A, L), functor_arityze(L, NL), remember_declarations(event, NL).
s2p((fluents A), fluents(NL)) :- nonvar(A), !,
	comma_to_list(A, L), functor_arityze(L, NL), remember_declarations(fluent, NL).

%	8b: the one new construct (§I.7.2). `achieve F1, F2, ...` names a
%	conjunction of fluents to be reached; everything else about the program
%	— the causal laws, the denials — is unchanged, which is the whole point.
s2p((achieve Goals), achieve(List)) :- !,
	comma_to_list(Goals, List),
	remember_hints(fluent, List).

%	9: reactive rules
s2p((if A then C), reactive_rule(NA, NC)) :- !,
	s2p_sequence(A, [_T1, _T2], _IT, _ETA, NA),
	s2p_sequence(C, [_T3, _T4], _IT2, _ETC, NC).

%	10: integrity constraints / preconditions
s2p((false B), d_pre(IC)) :- !,
	s2p_sequence(B, [_T1, _T2], single, _ET, IC).

%	11: post-conditions with a body
s2p(Surface, PT) :-
	Surface = (H if B),
	(   H = (Event initiates Fluent), PT = initiated(NB1, Fluent, NBn)
	;   H = (Event terminates Fluent), PT = terminated(NB1, Fluent, NBn)
	;   H = (Event updates Old to New in Fluent), PT = updated(NB1, Fluent, Old-New, NBn)
	),
	!,
	( var(Event) -> Event = happens(_, _, _) ; true ),
	remember_fluent_hint(Fluent), remember_event_hint(Event),
	s2p_literal(Event, [T1, T2], _ETL, NB1),
	s2p_sequence(B, [T1, T3], single, _ET, NBn),
	( T3 \== T1 -> T2 = T3 ; true ).      % don't collapse the event's interval

%	12: post-conditions without a body
s2p(H, PT) :-
	(   H = (Event initiates Fluent), PT = initiated(NB1, Fluent, NBn)
	;   H = (Event terminates Fluent), PT = terminated(NB1, Fluent, NBn)
	;   H = (Event updates Old to New in Fluent), PT = updated(NB1, Fluent, Old-New, NBn)
	),
	!,
	( var(Event) -> Event = happens(_, _, _) ; true ),
	remember_fluent_hint(Fluent), remember_event_hint(Event),
	s2p_sequence(Event, [_T1, _T2], single, _ET, [NB1|NBn]).

%	13: intensional fluents and composite events
s2p(Surface, PT) :-
	Surface = (Head if Body),
	s2p_literal(Head, [T1, T2], ETH, NH),
	(   PT = l_events(NH, NB), NH = happens(_, _, _)
	;   PT = l_int(NH, NB), NH = holds(_, _), remember_fluent_hint(Head)
	),
	!,
	( PT = l_int(_, _) -> IntervalType = single ; true ),
	s2p_sequence(Body, [T1body, T2body], IntervalType, _ETbody, NB),
	%  head and body intervals are fused only when the head has no explicit
	%  time; a fluent head always fuses, since it names a single instant
	( NH = holds(_, _) -> T2body = T2, T1body = T1 ; true ),
	( ETH == (false) -> T2body = T2, T1body = T1 ; true ).

s2p((H :- B), _) :- ( var(H) ; var(B) ), !, fail.

%	14: time-dependent facts
s2p(Head, l_int(WHead, [])) :-
	s2p_literal(Head, [_T1, _T2], _, WHead), WHead = holds(_, _), !.
s2p(Head, l_events(WHead, [])) :-
	s2p_literal(Head, [_T1, _T2], _, WHead), WHead = happens(_, _, _), !.

%	15: anything else is ordinary Prolog and passes through
s2p(Term, Term).

		 /*******************************
		 *	    observations	*
		 *******************************/

%	`observe a, b, c from T1 to T2` — every observation in the list shares
%	one end time, which is what `observe/2` records.
s2p_observations(CL, CommaT2, [E], CommonT2) :-
	( nonvar(CL) -> \+ functor(CL, ',', 2) ; true ), !,
	s2p_one_observation(CL, CommaT2, E, CommonT2).
s2p_observations((Ob, CL), CommaT2, [E|L], CommonT2) :-
	s2p_one_observation(Ob, CommaT2, E, CommonT2),
	s2p_observations(CL, CommaT2, L, CommonT2).

s2p_one_observation((E from _ to CT2), T2, E, LT2) :- !, CT2 = T2, CT2 = LT2, remember_event_hint(E).
s2p_one_observation((E to CT2), T2, E, LT2) :- !, T2 = CT2, CT2 = LT2, remember_event_hint(E).
s2p_one_observation((E at CT2), T2, E, LT2) :- atom(CT2), !, T2 = CT2, CT2 = LT2, remember_event_hint(E).
s2p_one_observation(E, T2, E, T2) :- remember_event_hint(E).

		 /*******************************
		 *	     sequences		*
		 *******************************/

%!	s2p_sequence(+Surface, ?Interval, ?IntervalType, -ExplicitTime, -Literals)
%
%	IntervalType == single means the sequence must span a single
%	transition — two consecutive cycles. Post-conditions, preconditions and
%	intensional-fluent bodies are all `single`; reactive rules are not.
s2p_sequence(NS, _, _, _, _) :- var(NS), !, fail.
s2p_sequence((L1, L2), [T1, T6], IT, ET, [PT1|PT2]) :-
	PT2 \== [], !,
	s2p_literal(L1, [T2, T3], ETL, PT1),
	s2p_sequence(L2, [T4, T5], IT, ETS, PT2),
	( ( ETL == (false), ETS == (false) ) -> ET = (false) ; ET = true ),
	(   IT == single
	->  (   %  L1: a fluent or timeless literal with no explicit time starts
		%  where the sequence starts; an event spans the whole interval
		(   ( T2 == T3, ETL == (false) ) -> T1 = T2
		;   PT1 = happens(_, _, _) -> ( T1 = T2, T6 = T3 )
		;   true                              % a fluent with explicit time
		),
		(   ( T4 == T5, ETS == (false) )
		->  ( T4 = T1, ( T2 == T3 -> T5 = T6 ; true ) )
		;   memberchk(happens(_, _, _), PT2) -> ( T1 = T4, T6 = T5 )
		;   true
		)
	    )
	;   %  Not a single transition. `untimed_are_relaxed` is upstream's
	    %  default (its comment says "Bob's preference"), so consecutive
	    %  untimed literals are *not* forced to be adjacent in time.
	    T1 = T2, T6 = T5
	).
s2p_sequence(true, [T, T], _, (false), []) :- !.
s2p_sequence(L, Interval, _, ET, [PT]) :- s2p_literal(L, Interval, ET, PT).

		 /*******************************
		 *	     literals		*
		 *******************************/

%!	s2p_literal(+Surface, ?Interval, -ExplicitTime, -Internal)
%
%	For events Interval is [Start, End]; for fluents both elements are the
%	one instant. ExplicitTime is true when the surface literal named its
%	own time.

% ----- conditional expressions -----
s2p_literal((if Cond then Then else Else), [T1, T2], ET, (CondW -> ThenW ; ElseW)) :- !,
	s2p_sequence(Cond, [T1, TC], _, ETC, CondW),
	s2p_sequence(Then, [TT, T2], _, ETT, ThenW),
	s2p_sequence(Else, [_TE, T2], _, ETE, ElseW),
	( ( ETC == (false), ETT == (false), ETE == (false) ) -> ET = (false) ; ET = true ),
	( ( ETC == (false), ETT == (false) ) -> TC = TT ; true ).
s2p_literal((Cond -> Then ; Else), Interval, ET, W) :- !,
	s2p_literal((if Cond then Then else Else), Interval, ET, W).
%	The else branch of a bare `if C then T` is `[true]`, not `[]`: upstream
%	pins it in the head of this clause, so the empty-sequence shortcut in
%	s2p_sequence/5 never applies to it.
s2p_literal((if Cond then Then), Interval, ET, (CondW -> ThenW ; [true])) :- !,
	s2p_literal((if Cond then Then else true), Interval, ET, (CondW -> ThenW ; [true])).

% ----- editing actions: initiate/terminate/update -----
s2p_literal(NT, [T1, T2], ET, happens(NEA, T1, T2)) :-
	nonvar(NT), NT =.. [EA, LT],
	( EA = initiate ; EA = terminate ),
	(   LT = (L from T1_), ( var(T1_) ; is_some_time(T1_) ), T1 = T1_, ET = true
	;   LT = (L to T2), ET = true
	;   LT = (L from T1 to T2), ET = true
	;   LT = (L during [T1, T2]), ET = true
	;   LT = L, ET = (false)
	),
	!,
	remember_fluent_hint(L),
	NEA =.. [EA, L].
s2p_literal(update(in(to(Old, New), LT)), [T1, T2], ET, happens(update(Old-New, L), T1, T2)) :-
	(   LT = (L from T1_), ( var(T1_) ; is_some_time(T1_) ), T1 = T1_, ET = true
	;   LT = (L to T2), ET = true
	;   LT = (L from T1 to T2), ET = true
	;   LT = (L during [T1, T2]), ET = true
	;   LT = L, ET = (false)
	),
	!,
	remember_fluent_hint(L).

% ----- events with explicit time -----
s2p_literal(LT, [T1, T2], true, happens(RealNL, T1, T2)) :-
	nonvar(LT),
	(   LT = (L from T1_), ( var(T1_) ; is_some_time(T1_) ), T1 = T1_
	;   LT = (L to T2), ( var(T2) ; is_some_time(T2) )
	;   LT = (L from T1 to T2)
	;   LT = (L during [T1, T2])
	),
	nonvar(L),
	!,
	( L = not(RealL) -> RealNL = not(RealL) ; L = RealL, RealNL = L ),
	remember_event_hint(RealL).

% ----- meta-eventing: an internal-form literal written directly -----
s2p_literal(LT, [T1, T2], (false), happens(NL, T1, T2)) :-
	nonvar(LT), LT = happens(NL, T1, T2), !.

% ----- bare events, recognised by what the file has already said -----
s2p_literal(LT, [T1, T2], (false), happens(LT, T1, T2)) :-
	nonvar(LT),
	( LT = not(RealLT) -> true ; RealLT = LT ),
	( head_hint(RealLT, event) ; head_hint(RealLT, action) ),
	!.

% ----- negated fluents -----
s2p_literal(LT, [T1, T2], ET, holds(not(F), T)) :-
	(   LT = (not(F) at T), ( var(T) ; is_some_time(T) ), ET = true
	;   LT = not(F at T), ( var(T) ; is_some_time(T) ), ET = true
	;   LT = not(F), head_hint(F, fluent), ET = (false)
	),
	!,
	remember_fluent_hint(F),
	T1 = T, T2 = T.
s2p_literal(not(FS), [T1, T2], ET, holds(not(NL), T)) :-
	s2p_sequence(FS, [T1, T2], single, ET, NL),
	memberchk(holds(_, _), NL),
	!,
	T1 = T.

% ----- findall over a fluent conjunction -----
s2p_literal(LT, [T1, T2], ET, holds(findall(X, WFS, L), T)) :-
	(   LT = (findall(X, FS, L) at T), ET = true
	;   LT = findall(X, FS, L), ET = (false)
	),
	s2p_sequence(FS, [T1, T2], single, _ET, WFS),
	memberchk(holds(_, _), WFS),
	!,
	T1 = T, T2 = T.

% ----- fluents -----
s2p_literal(LT, [T1, T2], true, holds(F, T)) :-
	nonvar(LT), LT = (F at T), ( var(T) ; is_some_time(T) ),
	!,
	T = T1, T = T2,
	remember_fluent_hint(F).
s2p_literal(F, [T1, T2], (false), holds(F, T)) :-
	nonvar(F),
	( head_hint(F, fluent) ; system_fluent_template(F) ),
	!,
	T = T1, T = T2.
s2p_literal(F, [T1, T2], (false), holds(NL, T)) :-
	nonvar(F), F = holds(NL, T),
	!,
	T = T1, T = T2.

% ----- anything else is timeless -----
s2p_literal(L, [T, T], (false), L) :- may_add_timeless_ref(L).

system_fluent_template(real_time(_)).
system_fluent_template(lps_user(_)).
system_fluent_template(lps_user(_, _)).

		 /*******************************
		 *	       hints		*
		 *******************************/

head_hint(X, Sort) :- nonvar(X), head_hint(X, Sort, _), !.

remember_hint(Type, H) :-
	nonvar(Type), nonvar(H),
	memberchk(Type, [fluent, event, action, timeless]),
	functor(H, F, N), functor(HH, F, N),
	(   head_hint(HH, Type, _) -> true ; assertz(head_hint(HH, Type, (false))) ).
remember_hint(_, _).

remember_declaration(Type, H) :-
	nonvar(Type), nonvar(H),
	memberchk(Type, [fluent, event, action, timeless]),
	functor(H, F, N), functor(HH, F, N),
	(   head_hint(HH, Type, true)
	->  true
	;   retractall(head_hint(HH, Type, _)), assertz(head_hint(HH, Type, true))
	).
remember_declaration(_, _).

remember_hints(_Type, X) :- var(X), !.
remember_hints(_Type, []) :- !.
remember_hints(Type, [X1|Xn]) :- !, remember_hint(Type, X1), remember_hints(Type, Xn).
remember_hints(Type, X) :- remember_hint(Type, X).

remember_declarations(_Type, X) :- var(X), !.
remember_declarations(_Type, []) :- !.
remember_declarations(Type, [X1|Xn]) :- !,
	remember_declaration(Type, X1), remember_declarations(Type, Xn).
remember_declarations(Type, X) :- remember_declaration(Type, X).

remember_event_hint(X) :- var(X), !.
remember_event_hint((E from _T1 to _T2)) :- !, remember_event_hint(E).
remember_event_hint((E during _Interval)) :- !, remember_event_hint(E).
remember_event_hint(TL) :- remember_hint(event, TL).

remember_fluent_hint(X) :- var(X), !.
remember_fluent_hint((F at _T)) :- !, remember_fluent_hint(F).
remember_fluent_hint(TL) :- remember_hint(fluent, TL).

remember_timeless_hint(TL) :- remember_hint(timeless, TL).

may_add_timeless_ref(G) :-
	nonvar(G),
	functor(G, F, N),
	(   current_top_term(F/N) -> true
	;   timeless_ref(F/N) -> true
	;   assertz(timeless_ref(F/N))
	).
may_add_timeless_ref(_).

		 /*******************************
		 *   pass-through declarations	*
		 *******************************/

/* Terms already in the internal vocabulary, plus the list forms of the
   declarations. They are copied through unchanged, but their hints are still
   recorded — that is what lets a program declare `fluents [f(_)]` in internal
   form and then write `f(x)` bare in a surface rule.
*/
do_not_transform_may_hint(T) :- var(T), !, fail.
do_not_transform_may_hint(observe(Events, _)) :- !, remember_hints(event, Events).
do_not_transform_may_hint(fluent(F)) :- !, remember_declarations(fluent, F).
do_not_transform_may_hint(fluents(Fls)) :- is_list(Fls), !, remember_declarations(fluent, Fls).
do_not_transform_may_hint(event(E)) :- !, remember_declarations(event, E).
do_not_transform_may_hint(events(Evs)) :- is_list(Evs), !, remember_declarations(event, Evs).
do_not_transform_may_hint(prolog_events(Evs)) :- is_list(Evs), !, remember_declarations(event, Evs).
do_not_transform_may_hint(action(A)) :- !, remember_declarations(action, A).
do_not_transform_may_hint(actions(As)) :- is_list(As), !, remember_declarations(action, As).
do_not_transform_may_hint(unserializable(As)) :- is_list(As), !.
do_not_transform_may_hint(initial_state(S)) :- !, remember_hints(fluent, S).
do_not_transform_may_hint(l_int(_, _)).
do_not_transform_may_hint(l_events(_, _)).
do_not_transform_may_hint(l_timeless(_, _)).
do_not_transform_may_hint(initiated(_, _, _)).
do_not_transform_may_hint(terminated(_, _, _)).
do_not_transform_may_hint(updated(_, _, _, _)).
do_not_transform_may_hint(reactive_rule(_, _, _)).
do_not_transform_may_hint(reactive_rule(_, _)).
do_not_transform_may_hint(d_pre(_)).
do_not_transform_may_hint(maxTime(_)).
do_not_transform_may_hint(maxRealTime(_)).
do_not_transform_may_hint(minCycleTime(_)).
do_not_transform_may_hint(simulatedRealTimePerCycle(_)).
do_not_transform_may_hint(simulatedRealTimeBeginning(_)).

		 /*******************************
		 *	     helpers		*
		 *******************************/

comma_to_list(NS, _) :- var(NS), !, fail.
comma_to_list((One, Two), [One|Twol]) :- !, comma_to_list(Two, Twol).
comma_to_list(One, [One]).

%	`foo/2` in a declaration list means the template foo(_,_).
functor_arityze([F/A|T], [G|L]) :- atom(F), integer(A), !, functor(G, F, A), functor_arityze(T, L).
functor_arityze([T|Ts], [T|L]) :- !, functor_arityze(Ts, L).
functor_arityze([], []).
