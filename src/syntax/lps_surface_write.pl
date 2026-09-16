/* lps_surface_write.pl — the internal representation, written back as LPS.

   The front ends (PDDL §IV.3, Drools §IV.4) produce §I.3 internal syntax:
   `initiated/3`, `d_pre/1`, `reactive_rule/2`, `happens/3`, `holds/2`. That is
   the right *target* — it is what the compiler consumes — and the wrong thing
   to put in an editor. A student who opens a converted domain should see the
   language the tutorial teaches:

       pick_up(X) terminates ontable(X).
       false pick_up(X) from T1 to T2, not clear(X) at T1.

   not

       terminated(happens(pick_up(A),B,C), ontable(A), []).
       d_pre([happens(pick_up(A),B,C), holds(not(clear(A)),B)]).

   So this module inverts lps_legacy_syntax's `s2p/2`. Two decisions make that
   safe rather than hopeful:

   1. It builds a *term* and lets `write_term/2` print it under the operator
      table, instead of assembling text. A term written with `quoted(true)`
      under the same operators the reader will use is a term that reads back;
      string assembly is where quoting bugs live (`'pick-up'(X)` is one
      character away from a syntax error).

   2. It checks itself. `internal_to_surface/3` re-reads what it wrote, pushes
      it through `legacy_to_internal/4`, and compares the result with its input
      up to variable renaming. If they differ it says so, and the caller keeps
      the internal rendering. A converted buffer that no longer means what the
      converter said is worse than an ugly one.

   Times are always written explicitly (`F at T`, `E from T1 to T2`). The
   surface language will infer them, but its inference is the *relaxed* one —
   two untimed fluent literals in a reactive rule get two different times —
   and the internal terms being rendered here often share one. Explicit is
   what round-trips, and it is also what `examples/start/goat_declarative.pl` does by
   hand for exactly the same reason.
*/

:- module(lps_surface_write, [
	internal_to_surface/3,     % +Terms, -Text, -Diags
	surface_term/2             % +InternalTerm, -SurfaceTerm
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').
:- use_module(lps_legacy_syntax).

%!	internal_to_surface(+Terms, -Text, -Diags) is det.
%
%	Terms are internal terms or `t(Term, Provenance)` pairs, in file order.
%	Text is LPS surface syntax. Diags carries one warning if the round-trip
%	check failed, in which case the caller should not use Text.
internal_to_surface(Terms0, Text, Diags) :-
	maplist(strip_provenance, Terms0, Terms),
	with_output_to(string(Text), write_surface_terms(Terms)),
	(   roundtrips(Terms, Text)
	->  Diags = []
	;   diag(warning, surface_roundtrip, unknown,
		 'the surface rendering did not read back as the same program',
		 D),
	    Diags = [D]
	).

strip_provenance(t(T, _), T) :- !.
strip_provenance(T, T).

%	The check. `legacy_to_internal/4` is the reader this text will meet, so
%	run exactly that, and compare term by term: same count, same order,
%	variant up to renaming. Declarations are compared too — they are what
%	teaches the reader which bare literal is a fluent, so a declaration lost
%	in translation changes the meaning of everything after it.
roundtrips(Terms, Text) :-
	catch(read_surface_terms(Text, Raw), _, fail),
	legacy_to_internal(terms(Raw), [], Back0, Diags),
	\+ ( member(diag(error, _, _, _, _), Diags) ),
	maplist(strip_provenance, Back0, Back),
	same_length(Terms, Back),
	forall(nth0(I, Terms, A),
	       ( nth0(I, Back, B), same_meaning(A, B) )).

%	Equal up to variable renaming, with one documented exception: a Drools
%	`salience` arrives as `reactive_rule/3` and there is no surface syntax
%	for it. It is written out as a comment instead, and the engine itself
%	drops it — lps_program.pl collects `reactive_rule(A,C)` and
%	`reactive_rule(A,C,_)` into one list — so the rule that comes back means
%	exactly what the rule that went in meant.
same_meaning(A, B) :- A =@= B, !.
same_meaning(reactive_rule(C, X, _), reactive_rule(C, X2)) :- X =@= X2, !.
same_meaning(reactive_rule(C, X, _), reactive_rule(C2, X2)) :-
	reactive_rule(C, X) =@= reactive_rule(C2, X2).

read_surface_terms(Text, Terms) :-
	setup_call_cleanup(
	    open_string(Text, In),
	    read_all_terms(In, Terms),
	    close(In)).

read_all_terms(In, Terms) :-
	read_term(In, T, [module(lps_ops)]),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [T|Rest], read_all_terms(In, Rest)
	).


		 /*******************************
		 *	     the writer		*
		 *******************************/

/*  The layout keeps *internal* literals, and the printer below knows which
    positions are constructs and which are leaves. That distinction is not
    decoration: `examples/planning/gripper-domain.pddl` has a fluent called
    `at/2`, so a printer that pattern-matched on `at` in a surface term
    rendered `holds(not(at(A,B)), T)` as `not A at B at T` — an operator
    priority clash, and the only reason the round-trip check exists. Leaves are
    written at the priority their position allows, so a fluent whose functor is
    an operator gets its brackets and reads back as itself.  */

%	A blank line whenever the kind of thing being written changes — the
%	declarations in one block, the causal laws in another, the denials in a
%	third. That is how every example in the corpus is laid out, and the point
%	of this module is that the output looks like one.
write_surface_terms(Terms) :-
	foldl(write_next, Terms, none, _).

write_next(T, Prev, Kind) :-
	( term_kind(T, K) -> Kind = K ; Kind = other ),
	(   ( Prev == none ; Prev == Kind ) -> true ; nl ),
	write_one(T).

term_kind(T, _) :- var(T), !, fail.
term_kind(fluents(_), declaration).
term_kind(events(_), declaration).
term_kind(prolog_events(_), declaration).
term_kind(actions(_), declaration).
term_kind(unserializable(_), declaration).
term_kind(maxTime(_), setting).
term_kind((:- _), setting).
term_kind(initial_state(_), initial).
term_kind(observe(_, _), initial).
term_kind(initiated(_, _, _), law).
term_kind(terminated(_, _, _), law).
term_kind(updated(_, _, _, _), law).
term_kind(d_pre(_), constraint).
term_kind(reactive_rule(_, _), rule).
term_kind(reactive_rule(_, _, _), rule).
term_kind(achieve(_), goal).
term_kind(_, other).

write_one(T) :-
	(   var(T) -> true
	;   surface_layout(T, Layout)
	    %  `\+ \+` because naming the variables *binds* them, and the layout
	    %  shares its variables with the term the caller handed us: without
	    %  this the round-trip check would compare a numbervar'd input with a
	    %  freshly-read copy and always disagree.
	->  \+ \+ ( anonymise_templates(Layout),
		    name_variables(Layout),
		    emit(Layout) )
	;   %  Nothing better to say than the term itself. Ordinary Prolog
	    %  clauses land here, and that is correct: they are already surface
	    %  syntax.
	    \+ \+ ( numbervars(T, 0, _),
		    portray_clause(current_output, T,
				   [numbervars(true), quoted(true)]) )
	).

%!	surface_layout(+Internal, -Layout) is semidet.
surface_layout(maxTime(N), term(maxTime(N))) :- !.
surface_layout((:- D),     directive(D)) :- !.
surface_layout(fluents(L), decl(fluents, L)) :- !.
surface_layout(events(L),  decl(events, L)) :- !.
surface_layout(prolog_events(L), decl(prolog_events, L)) :- !.
surface_layout(actions(L), decl(actions, L)) :- !.
surface_layout(unserializable(L), decl(unserializable, L)) :- !.
surface_layout(initial_state(L), decl(initially, L)) :- !.
surface_layout(achieve(L), decl(achieve, L)) :- !.
surface_layout(observe(Es, T), observation(Es, T)) :- !.
surface_layout(initiated(Ev, F, Body), law(Ev, initiates, F, Body)) :- !.
surface_layout(terminated(Ev, F, Body), law(Ev, terminates, F, Body)) :- !.
surface_layout(updated(Ev, F, Old-New, Body),
	       law(Ev, updates, update(Old, New, F), Body)) :- !.
surface_layout(d_pre(Lits), denial(Lits)) :- !.
surface_layout(reactive_rule(Cond, Concl), rule(Cond, Concl, none)) :- !.
surface_layout(reactive_rule(Cond, Concl, Pri), rule(Cond, Concl, Pri)) :- !.
surface_layout(l_int(Head, Body), clause_(Head, Body)) :- !.
surface_layout(l_events(Head, Body), clause_(Head, Body)) :- !.
surface_layout(l_timeless(Head, Body), timeless(Head, Body)) :- !.

		 /*******************************
		 *	  variable names	*
		 *******************************/

/*  `_G123` in an editor is noise. Time variables are named T1, T2, … in the
    order they appear, and everything else gets numbervars' letters — the
    convention every example in the corpus already follows. Naming times apart
    matters more than it looks: after this pass a reader can see at a glance
    which literals share an instant, which is the whole content of a denial
    like `false a at T, b at T`. */
name_variables(Layout) :-
	term_variables(Layout, Vars),
	time_variables(Layout, Times0),
	include(var_member(Vars), Times0, Times1),
	dedup_vars(Times1, Times),
	name_times(Times, 1),
	numbervars(Layout, 0, _).

var_member(Vars, V) :- var(V), \+ \+ ( member(X, Vars), X == V ).

dedup_vars([], []).
dedup_vars([V|Vs], [V|Rest]) :-
	exclude(==(V), Vs, Vs1),
	dedup_vars(Vs1, Rest).

name_times([], _).
name_times([V|Vs], N) :-
	format(atom(Name), 'T~w', [N]),
	V = '$VAR'(Name),
	N1 is N + 1,
	name_times(Vs, N1).

%	Where a time sits in the *internal* representation: `holds/2`'s second
%	argument and `happens/3`'s second and third. Collected left to right.
time_variables(T, []) :- var(T), !.
time_variables(holds(_, T), [T]) :- !.
time_variables(happens(_, T1, T2), [T1, T2]) :- !.
time_variables(T, Times) :-
	compound(T), !,
	T =.. [_|Args],
	foldl(collect_times, Args, [], Rev),
	reverse(Rev, Times).
time_variables(_, []).

collect_times(Arg, Acc0, Acc) :-
	time_variables(Arg, Ts),
	foldl([X, A, [X|A]]>>true, Ts, Acc0, Acc).

/*  A declaration names *templates*: `actions stack(_,_)`, not
    `actions stack(A,B)`. Named variables there would read back the same way —
    `functor_arityze` only looks at the shape — but they suggest a binding
    between the two arguments that does not exist. */
anonymise_templates(decl(Kind, List)) :-
	memberchk(Kind, [fluents, events, prolog_events, actions, unserializable]), !,
	term_variables(List, Vs),
	%  maplist, not forall: `forall/2` is a double negation and would undo
	%  every binding it made.
	maplist(=('$VAR'('_')), Vs).
anonymise_templates(_).

		 /*******************************
		 *	     emitting		*
		 *******************************/

emit(term(T)) :- !, write_leaf(T, 1200), format('.~n').
emit(directive(D)) :- !, format(':- '), write_leaf(D, 1199), format('.~n').
emit(decl(Kind, List)) :- !,
	format('~w ', [Kind]), leaf_list(List), format('.~n').
emit(observation(Es, T)) :- !,
	format('observe '), leaf_list(Es), format(' to '), write_leaf(T, 994),
	format('.~n').
emit(law(Ev, Op, What, Body)) :- !,
	print_lit(Ev), format(' ~w ', [Op]), print_effect(What),
	print_if(Body), format('.~n').
emit(denial(Lits)) :- !,
	format('false '), print_body(Lits), format('.~n').
emit(rule(Cond, Concl, Pri)) :- !,
	print_salience(Pri),
	format('if   '), print_body(Cond), nl,
	format('then '), print_body(Concl), format('.~n').
emit(clause_(Head, Body)) :- !,
	print_lit(Head), print_if(Body), format('.~n').
emit(timeless(Head, Body)) :- !,
	(   Body == []
	->  write_leaf(Head, 1199)
	;   write_leaf(Head, 1199), format(' :-\n    '), print_body(Body)
	),
	format('.~n').

/*  Salience has no surface syntax, and the engine drops it: lps_program.pl
    collects `reactive_rule(A,C)` and `reactive_rule(A,C,_)` into one list.
    Losing it silently would still be wrong — a Drools author set it on
    purpose — so it is recorded where the author will see it. */
print_salience(none) :- !.
print_salience(P) :- format('%  salience ~w in the source rule base (LPS has no rule priorities)~n', [P]).

print_effect(update(Old, New, F)) :- !,
	write_leaf(Old, 993), format(' to '), write_leaf(New, 996),
	format(' in '), write_leaf(F, 996).
print_effect(F) :- write_leaf(F, 1049).

print_if([]) :- !.
print_if(Body) :- format(' if '), print_body(Body).

print_body([]) :- !, format('true').
print_body([L]) :- !, print_lit(L).
print_body([L|Ls]) :- print_lit(L), format(', '), print_body(Ls).

%!	print_lit(+InternalLiteral) is det.
%
%	The four shapes the internal representation uses for a body literal, and
%	anything else written as an ordinary goal.
print_lit(V) :- var(V), !, write_leaf(V, 999).
print_lit(not(L)) :- !,
	%  A negated *timeless* literal — one with no time of its own. Written
	%  here rather than by write_term/2 so it comes out as `not foo(X)`
	%  instead of `not'foo'(X)`.
	format('not '), write_leaf(L, 900).
print_lit(holds(not(F), T)) :- !,
	format('not '), write_leaf(F, 900), format(' at '), write_leaf(T, 994).
print_lit(holds(F, T)) :- !,
	write_leaf(F, 994), format(' at '), write_leaf(T, 994).
print_lit(happens(not(E), T1, T2)) :- !,
	format('not '), write_leaf(E, 900), format(' from '), write_leaf(T1, 993),
	format(' to '), write_leaf(T2, 994).
print_lit(happens(E, T1, T2)) :- !,
	write_leaf(E, 994), format(' from '), write_leaf(T1, 993),
	format(' to '), write_leaf(T2, 994).
print_lit((C -> Then ; Else)) :- !,
	format('if '), print_body_or_lit(C),
	format(' then '), print_body_or_lit(Then),
	format(' else '), print_body_or_lit(Else).
print_lit(L) :- write_leaf(L, 999).

print_body_or_lit(L) :- is_list(L), !, print_body(L).
print_body_or_lit(L) :- print_lit(L).

leaf_list([]) :- !.
leaf_list([X]) :- !, write_leaf(X, 999).
leaf_list([X|Xs]) :- write_leaf(X, 999), format(', '), leaf_list(Xs).

%	A leaf is an ordinary term, written at the priority its position allows:
%	too high and an operator-headed fluent comes out ambiguous, too low and
%	the output is full of brackets nobody needs.
write_leaf(T, Priority) :-
	write_term(T, [ quoted(true), numbervars(true), priority(Priority),
			module(lps_ops) ]).

%!	surface_term(+InternalTerm, -Text) is semidet.
%
%	One term as surface text, for callers that want a line rather than a
%	file — the "see internal syntax" pane's inverse.
surface_term(Internal, Text) :-
	with_output_to(string(Text), write_one(Internal)).
