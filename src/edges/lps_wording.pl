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
	lps_worded/3,            % +Wording, +Term, -Sentence
	lps_worded_term/3        % +Wording, +Sentence, -Term     nondet
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

%!	lps_worded_term(+Wording, +Sentence, -Term) is nondet.
%
%	The other direction: Term is a term that a template of Wording says as
%	Sentence. `bob transfers 10 to alice` is transfer(bob, 10, alice) by
%	the template `*a payer* transfers *an amount* to *a payee*`. The words
%	of the template are matched whatever their case, and a full stop at
%	the end of Sentence is not part of it. A slot takes the text between
%	the words on each side of it: a number is read as a number, text in
%	double quotes as a string, and anything else as the atom of its words
%	in lower case with `_` for a space, which is how a scenario of the
%	document writes a name. Templates are tried in the document's order,
%	and a slot takes the shortest text that lets the rest match.
lps_worded_term(Wording, Sentence0, Term) :-
	text_to_string(Sentence0, S0),
	normalize_space(string(S1), S0),
	( string_concat(S2, ".", S1) -> normalize_space(string(S), S2) ; S = S1 ),
	S \== "",
	string_lower(S, Lower),
	member(wording(F, A, Pieces), Wording),
	length(Args, A),
	pieces_match(Pieces, S, Lower, 0, Args),
	Term =.. [F|Args].

%	Lower is Sentence in lower case: the words are found in it, and the
%	values are taken from Sentence at the same places.
pieces_match([], S, _, At, _) :-
	string_length(S, L),
	sub_string(S, At, _, 0, Rest), normalize_space(string(""), Rest),
	At =< L.
pieces_match([slot(K)|Pieces], S, Lower, At, Args) :- !,
	(   Pieces = [Words|_], Words \= slot(_)
	->  piece_words(Words, W),
	    (   W == ""
	    ->  sub_string(S, At, _, 0, Text), string_length(S, End)
	    ;   sub_string(Lower, B, _, _, W), B >= At,
	        word_at(Lower, B, W),
	        Len is B - At, sub_string(S, At, Len, _, Text), End = B
	    )
	;   Pieces == []
	->  sub_string(S, At, _, 0, Text), string_length(S, End)
	;   fail					% two slots with no word between them
	),
	slot_value(Text, V),
	nth0(K, Args, V),
	pieces_match(Pieces, S, Lower, End, Args).
pieces_match([Words|Pieces], S, Lower, At, Args) :-
	piece_words(Words, W),
	(   W == ""
	->  End = At
	;   sub_string(Lower, At, _, 0, Rest0),
	    string_length(Rest0, L0),
	    split_string(Rest0, "", " ", [Rest]), string_length(Rest, L1),
	    string_concat(W, _, Rest),
	    string_length(W, WL),
	    End is At + (L0 - L1) + WL,
	    word_end(Lower, End)
	),
	pieces_match(Pieces, S, Lower, End, Args).

piece_words(Words, W) :-
	text_to_string(Words, W0), normalize_space(string(W1), W0), string_lower(W1, W).

%	The words stand as whole words: `to` is not found inside `tom`.
word_at(Lower, B, W) :-
	( B =:= 0 -> true ; B1 is B - 1, sub_string(Lower, B1, 1, _, " ") ),
	string_length(W, WL), End is B + WL,
	word_end(Lower, End).

word_end(Lower, End) :-
	string_length(Lower, L),
	( End >= L -> true ; sub_string(Lower, End, 1, _, C), \+ char_type(C, alnum) ).

slot_value(Text0, V) :-
	normalize_space(string(Text), Text0),
	Text \== "",
	(   number_string(N, Text) -> V = N
	;   string_concat("\"", T1, Text), string_concat(Q, "\"", T1) -> V = Q
	;   string_lower(Text, L), split_string(L, " ", "", Parts),
	    atomic_list_concat(Parts, '_', V)
	).
