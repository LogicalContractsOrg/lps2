/* lps_wording.pl — a term of a run, said in the words of its document.

   A Logical English document declares a template for every fluent, event and
   action: `*a payer* transfers *an amount* to *a payee*`. The program that
   runs is made of terms, `transfer(bob, 10, alice)`, and a trace is made of
   the same terms. This module says one term of a trace the way the document
   would: `bob transfers 10 to alice`. The timeline's labels are its first
   reader (`operation("timeline")` in lps_api.pl).

   Nothing here asks Logical English anything. The templates arrive as LE2's
   `le_template(F/A, Role, Surface, Slots, Position, Flags)` terms, which is
   what `lps_le:lps_le_templates/3` returns and what the player's narrator
   already reads (lps_play.pl). So this file loads, and answers "no wording",
   in an image that has no Logical English at all.

   What needs saying out loud:

     - **Only the document's own words.** A program in the older syntax has
       no templates. Misc ▸ Convert to Logical English invents some
       (`loc(goat, south)` becomes `the loc of goat is south`), and they are
       a guess about English. A guess is right for a document the reader
       asked for and wrong for a label the reader did not: such a program
       has no wording here, and its timeline shows its terms.
     - **The arguments stand in the order of the slots.** The Kth `*slot*`
       of a surface is the Kth argument of the term: the surface language
       defines argument order that way (docs/user/reference/le-for-lps.md
       §2), and lps_play.pl reads commands by the same rule.
     - **A value is written as a scenario writes it.** A string keeps its
       quotes and a list its brackets, as LE2's own writer does
       (le_lps_write.pl, arg_text/3), so a label can be read back as the
       sentence it is.
*/

:- module(lps_wording, [
	lps_wording/2,           % +Templates, -Wording
	lps_worded/3             % +Wording, +Term, -Sentence
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).

%!	lps_wording(+Templates, -Wording) is det.
%
%	What it takes to say a term of a run: one `wording(Name, Arity,
%	Pieces)` for each fluent, event and action that Templates declares.
%	Pieces is the template's surface cut at its slots: a string for the
%	words, `slot(K)` for the Kth argument (0-based). A template of another
%	role (a timeless predicate, a built-in comparison) is left out: a trace
%	holds no term of that kind. Of two templates for one name, the one the
%	document declares first is kept.
lps_wording(Templates, Wording) :-
	findall(Start-wording(F, A, Pieces),
		( member(le_template(F/A, Role, Surface, _, Pos, _), Templates),
		  memberchk(Role, [fluent, event, action, prolog_event]),
		  surface_pieces(Surface, Pieces),
		  aggregate_all(count, member(slot(_), Pieces), A),
		  position_start(Pos, Start) ),
		Keyed0),
	keysort(Keyed0, Keyed),
	pairs_first_of_each(Keyed, [], Wording).

position_start(pos(Start, _, _, _), Start) :- integer(Start), !.
position_start(_, inf).

pairs_first_of_each([], _, []).
pairs_first_of_each([_-W|Rest], Seen, Ws) :-
	W = wording(F, A, _),
	(   memberchk(F/A, Seen)
	->  Ws = Ws1, Seen1 = Seen
	;   Ws = [W|Ws1], Seen1 = [F/A|Seen]
	),
	pairs_first_of_each(Rest, Seen1, Ws1).

%	`*a payer* transfers *an amount* to *a payee*` is
%	[slot(0), " transfers ", slot(1), " to ", slot(2)]: between two
%	asterisks is a slot, and everything else is the template's words.
surface_pieces(Surface, Pieces) :-
	split_string(Surface, "*", "", Parts),
	parts_pieces(Parts, words, 0, Pieces).

parts_pieces([], _, _, []).
parts_pieces([P|Ps], words, K, Pieces) :-
	( P == "" -> Pieces = Rest ; Pieces = [P|Rest] ),
	parts_pieces(Ps, slot, K, Rest).
parts_pieces([_|Ps], slot, K, [slot(K)|Rest]) :-
	K1 is K + 1,
	parts_pieces(Ps, words, K1, Rest).

%!	lps_worded(+Wording, +Term, -Sentence) is semidet.
%
%	Term in the words of its template, as a string. Fails when Wording has
%	no template for Term, and the caller then shows the term as it is. An
%	argument that is a variable is written `…`: the timeline's line for a
%	fluent's default (`balance(_, 0)`) reads `the balance of … is 0`.
lps_worded(Wording, Term, Sentence) :-
	callable(Term),
	Term =.. [F|Args], length(Args, A),
	memberchk(wording(F, A, Pieces), Wording),
	maplist(piece_text(Args), Pieces, Texts),
	atomic_list_concat(Texts, Text0),
	normalize_space(string(Sentence), Text0).

piece_text(Args, slot(K), Text) :- !,
	nth0(K, Args, Arg),
	value_text(Arg, Text).
piece_text(_, Words, Words).

value_text(V, '…') :- var(V), !.
value_text(V, T) :- string(V), !, format(atom(T), '"~w"', [V]).
value_text(V, T) :- is_list(V), !,
	maplist(value_text, V, Ts),
	atomic_list_concat(Ts, ', ', In),
	format(atom(T), '[~w]', [In]).
value_text(V, T) :- format(atom(T), '~w', [V]).
