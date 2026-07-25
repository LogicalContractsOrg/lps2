/* lps_terms.pl — term utilities shared by the resolver, the query evaluator
   and the state updater. Nothing here touches the store or the program; these
   are pure term operations, and they are separated out precisely so they can
   be unit-tested without an engine.
*/

:- module(lps_terms, [
	a_literal/2,             % +Sequence, -Literal    (nondet, left to right)
	flat_sequence/2,         % +Sequence, -Literals
	flat_sequence/3,
	simplify_conjunction/3,  % +G1, +G2, -G
	replace_term/4,          % +Term, +Find, +Replacement, -NewTerm
	my_term_size/2,          % +Term, -Size
	member_chk_variant/2,    % +X, +List
	member_equivalent_chk/2, % +X, +List              (==, not variant)
	lps_contains_var/2       % +Var, +Term
	]).

:- use_module(lps_ops).
:- use_module(library(lists)).
:- use_module(library(terms), [variant/2]).

%!	a_literal(+Sequence, -Literal) is nondet.
%
%	Every literal of a clause body, left to right, negated ones included.
a_literal(V, _) :- var(V), !, fail.
a_literal((G1, G2), H) :- !, ( a_literal(G1, H) ; a_literal(G2, H) ).
a_literal([G1|Gn], H) :- !, ( a_literal(G1, H) ; a_literal(Gn, H) ).
a_literal((C -> T ; E), H) :- !, ( a_literal(C, H) ; a_literal(T, H) ; a_literal(E, H) ).
a_literal(holds(F, T), holds(F, T)) :- !.
a_literal(happens(E, T1, T2), happens(E, T1, T2)) :- !.
a_literal(G, G) :- G \== [], G \== true.

%!	flat_sequence(+Sequence, -Literals) is nondet.
%
%	As a_literal/2 but collecting the whole list; nondet because an
%	if-then-else yields one list per branch.
flat_sequence(S, FS) :- flat_sequence(S, FS, []).

flat_sequence(V, _, _) :- var(V), !, fail.
flat_sequence((G1, G2), F1, Fn) :- !, flat_sequence(G1, F1, F2), flat_sequence(G2, F2, Fn).
flat_sequence([G1|Gn], F1, Fn) :- !, flat_sequence(G1, F1, F2), flat_sequence(Gn, F2, Fn).
flat_sequence((C -> T ; _E), F1, Fn) :- flat_sequence(C, F1, F2), flat_sequence(T, F2, Fn).
flat_sequence((C -> _T ; E), F1, Fn) :- !, flat_sequence((not C), F1, F2), flat_sequence(E, F2, Fn).
flat_sequence(holds(F, T), [holds(F, T)|Tail], Tail) :- !.
flat_sequence(happens(E, T1, T2), [happens(E, T1, T2)|Tail], Tail) :- !.
flat_sequence(true, Tail, Tail) :- !.
flat_sequence([], Tail, Tail) :- !.
flat_sequence(G, [G|Tail], Tail).

%!	simplify_conjunction(+G1, +G2, -G) is det.
simplify_conjunction(G1, G2, _) :-
	( var(G1) ; var(G2) ), !,
	throw(error(lps_bad_simplify_conjunction(G1, G2), _)).
simplify_conjunction(true, G, G) :- !.
simplify_conjunction(G, true, G) :- !.
simplify_conjunction(A, B, (A, B)).

%!	replace_term(+Term, +Find, +Replacement, -NewTerm) is det.
%
%	Find may be a single subterm or a list of them; used by `updates`
%	causal laws, where the change is written `Old-New`.
replace_term(Term, Find, Replacement, NewTerm) :-
	is_list(Find), !,
	replace_terms(Find, Replacement, Term, NewTerm).
replace_term(Term, Find, Replacement, NewTerm) :-
	replace_term_(Term, Find, Replacement, NewTerm).

replace_terms([Find|Subterms], [Replacement|Replacements], Term, NewTerm) :-
	replace_term_(Term, Find, Replacement, Term2),
	replace_terms(Subterms, Replacements, Term2, NewTerm).
replace_terms([], [], T, T).

replace_term_(Term, Find, Replacement, NewTerm) :- Term == Find, !, Replacement = NewTerm.
replace_term_(Term, _, _, NewTerm) :- ( atomic(Term) ; var(Term) ), !, Term = NewTerm.
replace_term_(Term, Find, Replacement, NewTerm) :-
	Term =.. [F|Args],
	replace_term_2(Args, Find, Replacement, NewArgs),
	NewTerm =.. [F|NewArgs].

replace_term_2([Term|Args], Find, Replacement, [NewTerm|NewArgs]) :- !,
	replace_term_(Term, Find, Replacement, NewTerm),
	replace_term_2(Args, Find, Replacement, NewArgs).
replace_term_2([], _, _, []).

%!	my_term_size(+Term, -Size) is det.
%
%	The size measure the `.lpst` contract uses to decide whether an item is
%	`lps_gigantic` (§0.2). Copied exactly; a different measure would move
%	the threshold and change what gets recorded.
my_term_size(T, 1) :- var(T), !.
my_term_size([T|TT], N) :- !, my_term_size(T, N1), my_term_size(TT, N2), N is N1 + N2.
my_term_size([], 1) :- !.
my_term_size(T, 1) :- atomic(T), !.
my_term_size(T, N) :- T =.. [_|L], my_term_size(L, N2), N is N2 + 1.

member_chk_variant(X, [XX|_]) :- variant(X, XX), !.
member_chk_variant(X, [_|L]) :- member_chk_variant(X, L).

member_equivalent_chk(X, [Y|_]) :- X == Y, !.
member_equivalent_chk(X, [_|L]) :- member_equivalent_chk(X, L).

%!	lps_contains_var(+Var, +Term) is semidet.
lps_contains_var(V, T) :-
	term_variables(T, Vs),
	member_equivalent_chk(V, Vs).
