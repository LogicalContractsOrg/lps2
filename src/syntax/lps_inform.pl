/* lps_inform.pl — Inform 7's assertion register as a front end
 * (docs/InformPlan.md phase 4, §5.1).
 *
 * Inform 7 source has two registers. Its *assertions* — `The Kitchen is a
 * room.`, `The oak door is a locked door. It is east of the Hall and west of
 * the Study.`, `Ogg is a man in the Donut Shop.` — are declarative and build
 * the initial world; the compiler turns each into a predicate-calculus
 * proposition. Its *rules* — `Instead of …`, `Every turn: …`, `Carry out …`
 * — are imperative phrases. This module translates the first register into a
 * Logical English story on examples/if/world.le, and reports every sentence
 * of the second as a diagnostic on its line, which is Part IV's rule for a
 * procedural leaf: say so, never approximate.
 *
 * What is translated:
 *
 *   X is a room.  X, Y and Z are rooms.  There is a room called X.
 *   X is a [props] KIND [in|on Y | carried by P | worn by P].
 *   X is [in|on] Y.  X is here.  X contains Y and Z.  In X is Y.  On X is Y.
 *   X is carried by P.  P carries X.  The player carries X.
 *   X is DIR of Y.  DIR of Y is X.  DIR is X.  X is DIR of Y and DIR2 of Z.
 *   X is closed/open/locked/unlocked/openable/lockable/enterable/edible/
 *        fixed in place/portable/transparent/scenery/undescribed.
 *   The matching key of X is Y.   X is a kind of KIND [which is props].
 *   "…" after a room, and The description of X is "…"  → the narrator's text
 *   Test me with "a / b / c".                            → the scenario
 *
 * KIND is one of Inform's: room, thing, container, supporter, door, person,
 * man, woman, animal, device, backdrop, vehicle — or a kind the source
 * declares (`A box is a kind of container which is closed and openable.`).
 * Objects are named by their words: `the Donut Shop` is `donut_shop`.
 *
 * The output is a `.le` document that includes `world`, and a `.lps`
 * companion for the descriptions; both are text, and the caller decides
 * where they go (beside a copy of the library, since an include is
 * resolved against the document's own directory).
 */

:- module(lps_inform, [
	inform_to_le/4,          % +File, -LEText, -CompanionText, -Diags
	inform_parse/3           % +File, -Sentences, -Diags   (for tests)
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pcre), []).
:- use_module('../core/lps_diag').

:- discontiguous assertion/1.

		 /*******************************
		 *	    sentences		*
		 *******************************/

%!	inform_parse(+File, -Sentences, -Diags) is det.
%
%	Sentences are `s(Line, Text)` in source order, quoted strings kept
%	as part of the text; comments in square brackets removed.
inform_parse(File, Sentences, []) :-
	read_file_to_string(File, S0, [encoding(utf8)]),
	strip_comments(S0, S1),
	split_sentences(S1, Sentences).

strip_comments(S0, S) :-
	re_replace("\\[[^\\]]*\\]"/g, "", S0, S1),
	string_codes(S1, Cs), atom_codes(S, Cs).

%	A sentence ends at a full stop outside quotes, or at a blank line, or
%	at a colon at the end of a line (a rule preamble). Quoted text may hold
%	full stops. Each sentence carries the line it started on.
split_sentences(Text, Sentences) :-
	string_codes(Text, Cs),
	split_(Cs, 1, 1, [], false, Sentences).

split_([], _, L, Acc, _, Ss) :- !, flush(Acc, L, Ss, []).
split_([0'"|Cs], Line, L0, Acc, false, Ss) :- !,
	split_(Cs, Line, L0, [0'"|Acc], true, Ss).
split_([0'"|Cs], Line, L0, Acc, true, Ss) :- !,
	%  A closing quote followed by a capital ends the sentence: `"…"
	%  Understand "og" as Ogg.` is two sentences with no full stop between.
	(   after_spaces(Cs, C), code_type(C, upper)
	->  flush([0'"|Acc], L0, Ss, Rest), split_(Cs, Line, Line, [], false, Rest)
	;   split_(Cs, Line, L0, [0'"|Acc], false, Ss)
	).
split_([0'\n|Cs], Line, L0, Acc, Q, Ss) :-
	Line1 is Line + 1,
	(   Q == false, blank_line(Cs)
	->  flush(Acc, L0, Ss, Rest), skip_blank(Cs, Line1, Cs1, Line2),
	    split_(Cs1, Line2, Line2, [], false, Rest)
	;   Q == false, Acc = [0':|_]
	->  %  A rule preamble: what follows, up to the next blank line, is its
	    %  body — phrases, not assertions — and is not read as sentences.
	    flush(Acc, L0, Ss, Rest), skip_block(Cs, Line1, Cs1, Line2),
	    split_(Cs1, Line2, Line2, [], false, Rest)
	;   split_(Cs, Line1, L0, [0' |Acc], Q, Ss)
	).
split_([0'.|Cs], Line, L0, Acc, false, Ss) :-
	\+ ( Cs = [C|_], code_type(C, alnum) ), !,
	flush(Acc, L0, Ss, Rest),
	split_(Cs, Line, Line, [], false, Rest).
split_([C|Cs], Line, L0, Acc, Q, Ss) :-
	( Acc == [], code_type(C, space) -> Acc1 = [], L1 = Line ; Acc1 = [C|Acc], L1 = L0 ),
	split_(Cs, Line, L1, Acc1, Q, Ss).

after_spaces([C|Cs], D) :- ( C == 0'\s ; C == 0'\t ; C == 0'\n ; C == 0'\r ), !, after_spaces(Cs, D).
after_spaces([C|_], C).

blank_line(Cs) :- append(Ws, [0'\n|_], Cs), \+ ( member(W, Ws), \+ code_type(W, space) ), !.
blank_line(Cs) :- \+ ( member(W, Cs), \+ code_type(W, space) ).

%	The body runs to the first blank line outside quotes: a `say` in it
%	may quote several paragraphs.
skip_block(Cs, L, Out, L2) :- skip_body(Cs, L, false, Out, L2).

skip_body([], L, _, [], L) :- !.
skip_body([0'"|Cs], L, Q, Out, L2) :- !, ( Q == true -> Q1 = false ; Q1 = true ), skip_body(Cs, L, Q1, Out, L2).
skip_body([0'\n|Cs], L, false, Out, L2) :- blank_line(Cs), !, L1 is L + 1, skip_blank(Cs, L1, Out, L2).
skip_body([0'\n|Cs], L, Q, Out, L2) :- !, L1 is L + 1, skip_body(Cs, L1, Q, Out, L2).
skip_body([_|Cs], L, Q, Out, L2) :- skip_body(Cs, L, Q, Out, L2).

skip_blank([0'\n|Cs], L, Out, L2) :- !, L1 is L + 1, skip_blank(Cs, L1, Out, L2).
skip_blank([C|Cs], L, Out, L2) :- code_type(C, space), !, skip_blank(Cs, L, Out, L2).
skip_blank(Cs, L, Cs, L).

flush(Acc, L, Ss, Rest) :-
	reverse(Acc, Cs), string_codes(S0, Cs), normalize_space(string(S), S0),
	( S == "" -> Ss = Rest ; Ss = [s(L, S)|Rest] ).

		 /*******************************
		 *	    the world		*
		 *******************************/

/*  Facts collected from the assertions:
      room(N)  kind(N, K)  prop(N, P)  in(N, H)  on(N, S)  carried(N, P)
      worn(N, P)  map(Dir, From, To)  door_map(Door, Dir, From, To)
      key(Lock, Key)  desc(N, Text)  user_kind(K, Base, Props)  script(Cmds)
    plus `last_room` and `last_subject` for `here` and `It`. */

:- dynamic w/1, last_room/1, last_subject/1.

reset :- retractall(w(_)), retractall(last_room(_)), retractall(last_subject(_)).
add(F) :- ( w(F) -> true ; assertz(w(F)) ).

%!	inform_to_le(+File, -LEText, -Companion, -Diags) is det.
inform_to_le(File, LEText, Companion, Diags) :-
	inform_parse(File, Sentences, D0),
	reset,
	findall(D, ( member(s(L, S), Sentences), sentence(File, L, S, D), D \== none ), D1),
	append(D0, D1, Diags),
	file_base_name(File, Base), file_name_extension(Stem, _, Base),
	story_name(Stem, Name),
	emit_le(File, Name, LEText),
	emit_companion(File, Companion).

story_name(Stem, Name) :-
	atom_codes(Stem, Cs),
	findall(C1, ( member(C, Cs), ( code_type(C, alnum) -> to_lower(C, C1) ; C1 = 0'_ ) ), Cs1),
	atom_codes(Name0, Cs1),
	( Name0 == '' -> Name = story ; Name = Name0 ).

%!	sentence(+File, +Line, +Text, -Diag) is det.
%
%	One sentence into facts, or a diagnostic. `none` when it was taken.
sentence(File, Line, Text, Diag) :-
	(   rule_register(Text, What)
	->  format(atom(M), 'not translated (~w): the rule register is not assertions — ~w', [What, Text]),
	    src(File, Line, Src), diag(warning, inform_rule, Src, M, Diag)
	;   catch(assertion(Text), _, fail)
	->  Diag = none
	;   format(atom(M), 'not translated: no assertion form matched — ~w', [Text]),
	    src(File, Line, Src), diag(warning, inform_unknown, Src, M, Diag)
	).

src(File, Line, src(File, Line, 0, inform)).

rule_register(Text, What) :-
	member(What-Prefix, [rule-"Before ", rule-"Instead of ", rule-"After ", rule-"Every turn",
			     rule-"Check ", rule-"Carry out ", rule-"Report ", rule-"When ",
			     rule-"At the time ", rule-"At ", rule-"Definition:", rule-"To ",
			     rule-"Rule for ", rule-"A persuasion rule", rule-"Persuasion rule",
			     rule-"Unsuccessful attempt", rule-"This is the ", rule-"The block ",
			     grammar-"Understand ", table-"Table of ", option-"Use ",
			     option-"Include ", heading-"Section ", heading-"Part ",
			     heading-"Chapter ", heading-"Book ", heading-"Volume ",
			     value-"The maximum score", action-"Litmus", rule-"Instead ",
			     action-"Shaking is an action", property-"A person can be",
			     property-"Food is a kind of thing", property-"Food has a",
			     property-"Ogg has a number", property-"The hunger of",
			     property-"The satisfaction period"]),
	sub_string(Text, 0, _, _, Prefix), !.
rule_register(Text, action) :-
	re_matchsub(" is an action applying to ", Text, _, []), !.
rule_register(Text, property) :-
	re_matchsub("^(A|An) [a-z ]+ (can be|has a|has an) ", Text, _, []), !.
rule_register(Text, value) :-
	re_matchsub(" is a kind of value", Text, _, []), !.


%	--- the forms, tried in order

assertion(Text) :- quoted_text(Text), !.
assertion(Text) :- test_me(Text), !.

%	A quoted sentence on its own: the description of what was last
%	declared — or the story's title, before anything was.
quoted_text(Text) :-
	re_matchsub("^\"(.*)\"\\.?$", Text, Sub, []),
	get_dict(1, Sub, D),
	( last_subject(N) -> add(desc(N, D)) ; true ).
assertion(Text) :- description_of(Text), !.
assertion(Text) :- kind_declaration(Text), !.
assertion(Text) :- matching_key(Text), !.
assertion(Text) :- there_is(Text), !.
assertion(Text) :- map_sentence(Text), !.
assertion(Text) :- contains_sentence(Text), !.
assertion(Text) :- carried_sentence(Text), !.
assertion(Text) :- is_a_sentence(Text), !.
assertion(Text) :- is_in_sentence(Text), !.
assertion(Text) :- property_sentence(Text), !.

%	Test me with "n / s / e / w".
test_me(Text) :-
	re_matchsub("^Test me with \"([^\"]*)\"\\.?$", Text, Sub, []),
	get_dict(1, Sub, S),
	split_string(S, "/", " ", Cmds0),
	exclude(==(""), Cmds0, Cmds),
	add(script(Cmds)).

%	The description of X is "…".
description_of(Text) :-
	re_matchsub("^The description of (?:the )?(.+?) is \"(.*)\"\\.?$", Text, Sub, [caseless(true)]),
	get_dict(1, Sub, N0), get_dict(2, Sub, D),
	object_name(N0, N), add(desc(N, D)).

%	A box is a kind of container which is closed and openable.
%	A sealed box is a kind of box which is not openable.
kind_declaration(Text) :-
	re_matchsub("^(?:A|An) (.+?) is a kind of (\\w+)(?: (?:which|that) is (.+?))?\\.?$", Text, Sub, [caseless(true)]),
	get_dict(1, Sub, K0), get_dict(2, Sub, Base0),
	object_name(K0, K), string_lower(Base0, BaseS), atom_string(Base, BaseS),
	(   get_dict(3, Sub, PropsS) -> prop_words(PropsS, Props) ; Props = [] ),
	add(user_kind(K, Base, Props)).

%	The matching key of the case is a silver key.
matching_key(Text) :-
	re_matchsub("^The matching key of (?:the )?(.+?) is (?:a |an |the )?(.+?)\\.?$", Text, Sub, [caseless(true)]),
	get_dict(1, Sub, L0), get_dict(2, Sub, K0),
	object_name(L0, L), object_name(K0, K),
	add(key(L, K)), ensure_thing(K).

%	There is a room called X.  There is a room.
there_is(Text) :-
	re_matchsub("^There is (?:a |an )?(\\w+)(?: called (?:the )?(.+?))?\\.?$", Text, Sub, [caseless(true)]),
	get_dict(1, Sub, K0), string_lower(K0, KS), atom_string(K, KS),
	(   get_dict(2, Sub, N0) -> object_name(N0, N) ; N = unnamed_room ),
	declare(N, K, []).

%	X is north of Y.  North of Y is X.  North is X.  It is east of the Hall
%	and west of the Study.  Garden is south of Home.
map_sentence(Text) :-
	re_matchsub("^(.+?) (?:is|are) (.+)\\.?$", Text, Sub, [caseless(true)]),
	get_dict(1, Sub, Subj0), get_dict(2, Sub, Rest),
	split_string(Rest, "", ".", [Rest1]),
	re_split(" and ", Rest1, Parts0),
	exclude(==(" and "), Parts0, Parts),
	Parts \== [],
	forall(member(P, Parts), map_clause(P, _)), !,
	subject(Subj0, Subj),
	forall(member(P, Parts), ( map_clause(P, c(Dir, Other)), map_add(Subj, Dir, Other) )).
map_sentence(Text) :-
	%  North of the Temple is the Approach.
	re_matchsub("^(\\w+) of (?:the )?(.+?) is (?:the )?(.+?)\\.?$", Text, Sub, [caseless(true)]),
	get_dict(1, Sub, D0), direction(D0, Dir),
	get_dict(2, Sub, From0), get_dict(3, Sub, To0),
	object_name(From0, From), object_name(To0, To),
	ensure_room(From), ensure_room(To),
	add(map(Dir, From, To)).
map_sentence(Text) :-
	%  The Sphinx is east.  (of the last room mentioned)
	re_matchsub("^(?:The |the )?(.+?) is (\\w+)\\.?$", Text, Sub, [caseless(true)]),
	get_dict(2, Sub, D0), direction(D0, Dir),
	get_dict(1, Sub, To0), object_name(To0, To),
	last_room(From), To \== From,
	ensure_room(To), add(map(Dir, From, To)), !.
map_sentence(Text) :-
	%  North is the Approach.  (from the last room mentioned)
	re_matchsub("^(\\w+) is (?:the )?(.+?)\\.?$", Text, Sub, [caseless(true)]),
	get_dict(1, Sub, D0), direction(D0, Dir),
	get_dict(2, Sub, To0), object_name(To0, To),
	last_room(From),
	ensure_room(To), add(map(Dir, From, To)).

map_clause(P, c(Dir, Other)) :-
	normalize_space(string(P1), P),
	re_matchsub("^(?:a room )?(\\w+) of (?:the )?(.+)$", P1, Sub, [caseless(true)]),
	get_dict(1, Sub, D0), direction(D0, Dir),
	get_dict(2, Sub, O0), object_name(O0, Other).

%	A door is a connection with the door in it; a room, a plain one.
map_add(Subj, Dir, Other) :-
	(   w(kind(Subj, door))
	->  ensure_room(Other),
	    opposite(Dir, Back),
	    %  "east of the Hall and west of the Study": the door is east of the
	    %  Hall, so from the Hall it leads east — to wherever its other side
	    %  is. Recorded as the door's sides; joined in emit.
	    add(door_side(Subj, Other, Back)),
	    ( \+ w(in(Subj, _)) -> add(in(Subj, Other)) ; true )
	;   ensure_room(Subj), ensure_room(Other),
	    add(map(Dir, Other, Subj))
	).

%	X contains Y and Z.  In X is Y and Z.  On X is Y.  In the box is a banana.
contains_sentence(Text) :-
	(   re_matchsub("^(?:The |the )?(.+?) contains (.+?)\\.?$", Text, Sub, [caseless(true)]),
	    get_dict(1, Sub, H0), get_dict(2, Sub, Items), Rel = in
	;   re_matchsub("^In (?:the )?(.+?) (?:is|are) (.+?)\\.?$", Text, Sub, [caseless(true)]),
	    get_dict(1, Sub, H0), get_dict(2, Sub, Items), Rel = in
	;   re_matchsub("^On (?:the )?(.+?) (?:is|are) (.+?)\\.?$", Text, Sub, [caseless(true)]),
	    get_dict(1, Sub, H0), get_dict(2, Sub, Items), Rel = on
	),
	object_name(H0, H),
	item_list(Items, Names),
	forall(member(N-Kind-Props, Names),
	       ( declare(N, Kind, Props), place(N, Rel, H) )).

%	The silver key is carried by Ogg.  Ogg carries the key.  The player is
%	carrying a box.  The player carries a box.
carried_sentence(Text) :-
	(   re_matchsub("^(?:The |the )?(.+?) (?:is|are) (carried|worn) by (?:the )?(.+?)\\.?$", Text, Sub, [caseless(true)]),
	    get_dict(1, Sub, Items), get_dict(2, Sub, How), get_dict(3, Sub, P0)
	;   re_matchsub("^(?:The |the )?(.+?) (?:carries|is carrying|wears|is wearing) (.+?)\\.?$", Text, Sub, [caseless(true)]),
	    get_dict(1, Sub, P0), get_dict(2, Sub, Items),
	    ( sub_string(Text, _, _, _, "wear") -> How = "worn" ; How = "carried" )
	),
	object_name(P0, P),
	item_list(Items, Names),
	forall(member(N-Kind-Props, Names),
	       ( declare(N, Kind, Props),
		 ( How == "worn" -> add(worn(N, P)) ; add(carried(N, P)) ) )).

%	X is a [props] KIND [in|on Y].  X, Y and Z are rooms.
%	The Donut Shop contains a … container called a case — handled by
%	contains; here: "Ogg is a man in the Donut Shop", "The case is a
%	transparent closed openable locked lockable container", "The cube and
%	the ball are here", "The jewel box is a box".
is_a_sentence(Text) :-
	re_matchsub("^(.+?) (?:is|are) (?:a |an |some )?(.+?)\\.?$", Text, Sub, [caseless(true)]),
	get_dict(1, Sub, Subj0), get_dict(2, Sub, Rest1),
	%  "a box which is not openable": properties after the kind
	(   re_matchsub("^(.+?) (?:which|that) (?:is|are) (.+)$", Rest1, SubW, [])
	->  get_dict(1, SubW, Rest0), get_dict(2, SubW, TailS), prop_words(TailS, TailProps)
	;   Rest0 = Rest1, TailProps = []
	),
	%  an optional location tail
	(   re_matchsub("^(.+?) (in|on) (?:the )?(.+)$", Rest0, Sub2, [])
	->  get_dict(1, Sub2, KindPart), get_dict(2, Sub2, RelS), get_dict(3, Sub2, Where0),
	    atom_string(Rel, RelS), object_name(Where0, Where), Loc = loc(Rel, Where)
	;   KindPart = Rest0, Loc = none
	),
	kind_and_props(KindPart, Kind, Props0),
	append(Props0, TailProps, Props),
	subject_list(Subj0, Subjs),
	forall(member(S, Subjs),
	       ( declare(S, Kind, Props),
		 ( Loc = loc(R, W) -> place(S, R, W) ; true ) )).

%	X is in Y.  X is on Y.  X, Y and Z are here.  X is here.
is_in_sentence(Text) :-
	(   re_matchsub("^(.+?) (?:is|are) (in|on) (?:the )?(.+?)\\.?$", Text, Sub, [caseless(true)]),
	    get_dict(1, Sub, Subj0), get_dict(2, Sub, RelS), get_dict(3, Sub, W0),
	    atom_string(Rel, RelS), object_name(W0, Where)
	;   re_matchsub("^(.+?) (?:is|are) here\\.?$", Text, Sub, [caseless(true)]),
	    get_dict(1, Sub, Subj0), Rel = in, last_room(Where)
	),
	subject_list(Subj0, Subjs),
	forall(member(S, Subjs), ( ensure_thing(S), place(S, Rel, Where) )).

%	The case is closed.  The oak door is closed and locked.  X is fixed in place.
property_sentence(Text) :-
	re_matchsub("^(.+?) (?:is|are) (.+?)\\.?$", Text, Sub, [caseless(true)]),
	get_dict(1, Sub, Subj0), get_dict(2, Sub, PropsS),
	prop_words(PropsS, Props), Props \== [],
	subject_list(Subj0, Subjs),
	forall(member(S, Subjs), ( ensure_thing(S), forall(member(P, Props), add(prop(S, P))) )).

%	--- pieces

%	"a transparent closed openable locked lockable container" → container +
%	props; "man" → person; a user kind → its base and its defaults.
kind_and_props(Text, Kind, Props) :-
	normalize_space(string(T), Text),
	split_string(T, " ", " ", Ws0), exclude(==(""), Ws0, Ws),
	maplist([S, A]>>( string_lower(S, L), atom_string(A, L) ), Ws, As),
	%  "container called a case" — the name is taken by the caller
	( append(As1, [called|_], As) -> true ; As1 = As ),
	%  The kind is the longest tail of the words that names one: "sealed
	%  box" before "box", so a two-word kind the source declared wins.
	append(Adjs, KindWords, As1), KindWords \== [],
	atomic_list_concat(KindWords, '_', KindWord0), plural_singular(KindWord0, KindWord),
	kind_word(KindWord, Kind, KindProps), !,
	adj_props(Adjs, Props0),
	append(KindProps, Props0, Props).

kind_word(K, Kind, []) :- base_kind(K, Kind), !.
kind_word(K, Kind, Props) :- w(user_kind(K, Base, Props0)), !, kind_word(Base, Kind, Props1), append(Props1, Props0, Props).

base_kind(room, room). base_kind(thing, thing). base_kind(container, container).
base_kind(supporter, supporter). base_kind(door, door). base_kind(person, person).
base_kind(man, person). base_kind(woman, person). base_kind(animal, person).
base_kind(device, thing). base_kind(backdrop, thing). base_kind(vehicle, container).
base_kind(region, region).

plural_singular(rooms, room) :- !.
plural_singular(things, thing) :- !.
plural_singular(containers, container) :- !.
plural_singular(supporters, supporter) :- !.
plural_singular(doors, door) :- !.
plural_singular(people, person) :- !.
plural_singular(men, man) :- !.
plural_singular(women, woman) :- !.
plural_singular(animals, animal) :- !.
plural_singular(W, S) :- atom_concat(S, s, W), base_kind(S, _), !.
plural_singular(W, W).

adj_props([], []).
adj_props([A|As], Ps) :-
	(   prop_word(A, P) -> Ps = [P|Rest] ; Ps = Rest ),
	adj_props(As, Rest).

%	"closed and locked", "not openable", "fixed in place"
prop_words(Text, Props) :-
	normalize_space(string(T), Text),
	re_split("(?:,\\s*(?:and )?| and )", T, Parts0),
	exclude([P]>>re_matchsub("^(?:,\\s*(?:and )?| and )$", P, _, []), Parts0, Parts),
	findall(P, ( member(S, Parts), normalize_space(atom(A), S), A \== '',
		     prop_phrase(A, P) ), Props).

prop_phrase(A, P) :- prop_word(A, P), !.
prop_phrase(A, P) :- atom_concat('not ', B, A), prop_word(B, Pos), negated(Pos, P), !.

prop_word(closed, closed). prop_word(open, open). prop_word(locked, locked).
prop_word(unlocked, unlocked). prop_word(openable, openable). prop_word(unopenable, unopenable).
prop_word(lockable, lockable). prop_word(enterable, enterable). prop_word(edible, edible).
prop_word(transparent, transparent). prop_word(opaque, opaque).
prop_word(scenery, fixed). prop_word('fixed in place', fixed). prop_word(portable, portable).
prop_word(undescribed, undescribed). prop_word(lit, lit). prop_word(dark, dark).
prop_word(wearable, wearable). prop_word(male, male). prop_word(female, female).

negated(openable, unopenable). negated(lockable, unlockable). negated(closed, open).
negated(open, closed). negated(locked, unlocked). negated(fixed, portable).

direction(S, D) :-
	string_lower(S, L), atom_string(A, L),
	memberchk(A, [north, south, east, west, up, down, northeast, northwest,
		      southeast, southwest, above, below, inside, outside]),
	( A == above -> D = up ; A == below -> D = down ; D = A ).

opposite(north, south). opposite(south, north). opposite(east, west). opposite(west, east).
opposite(up, down). opposite(down, up). opposite(northeast, southwest).
opposite(southwest, northeast). opposite(northwest, southeast). opposite(southeast, northwest).
opposite(inside, outside). opposite(outside, inside).

%	"The Donut Shop" → donut_shop; "some cake donuts" → cake_donuts; "It"
%	→ the last subject; "the player" → player.
object_name(S0, N) :-
	normalize_space(string(S1), S0),
	string_lower(S1, S2),
	re_replace("^(the|a|an|some) "/i, "", S2, S3),
	string_codes(S3, Cs),
	(   S3 == "it" -> last_subject(N)
	;   S3 == "the player" -> N = player
	;   S3 == "player" -> N = player
	;   findall(C1, ( member(C, Cs), ( code_type(C, alnum) -> C1 = C ; C1 = 0'_ ) ), Cs1),
	    atom_codes(N0, Cs1),
	    re_replace("_+"/g, "_", N0, N1), re_replace("^_|_$"/g, "", N1, N2),
	    atom_string(N3, N2),
	    %  "the donuts" for `cake_donuts`: a known name ending in these words.
	    (   known_object(N3) -> N = N3
	    ;   atom_concat('_', N3, Suffix), known_object(K), atom_concat(_, Suffix, K) -> N = K
	    ;   N = N3
	    )
	).

subject(S0, N) :- object_name(S0, N), set_subject(N).

set_subject(N) :-
	retractall(last_subject(_)), assertz(last_subject(N)),
	( w(room(N)) -> retractall(last_room(_)), assertz(last_room(N)) ; true ).

%	"The cube and the ball" → [cube, ball]; "X, Y and Z".
subject_list(S0, Ns) :-
	re_split("(?:,\\s*| and )", S0, Parts0),
	exclude([P]>>re_matchsub("^(?:,\\s*| and )$", P, _, []), Parts0, Parts),
	findall(N, ( member(P, Parts), normalize_space(string(P1), P), P1 \== "", object_name(P1, N) ), Ns),
	( Ns = [First|_] -> set_subject(First) ; true ).

%	"some cake donuts, some jelly donuts, and some apple fritters" or
%	"a transparent closed openable locked lockable container called a case"
%	→ Name-Kind-Props each.
item_list(S0, Items) :-
	re_split("(?:,\\s*(?:and )?| and )", S0, Parts0),
	exclude([P]>>re_matchsub("^(?:,\\s*(?:and )?| and )$", P, _, []), Parts0, Parts),
	findall(I, ( member(P, Parts), normalize_space(string(P1), P), P1 \== "", item(P1, I) ), Items).

item(P, N-Kind-Props) :-
	(   re_matchsub("^(?:a |an |some |the )?(.+?) called (?:a |an |the )?(.+)$", P, Sub, [caseless(true)])
	->  get_dict(1, Sub, KindPart), get_dict(2, Sub, N0),
	    object_name(N0, N), kind_and_props(KindPart, Kind, Props)
	;   object_name(P, N), Kind = thing, Props = []
	).

declare(N, Kind, Props0) :-
	normalise_props(Props0, Props),
	set_subject(N),
	(   Kind == room -> add(room(N)), retractall(last_room(_)), assertz(last_room(N))
	;   Kind == region -> add(region(N))
	;   Kind == thing -> ensure_thing(N)
	;   add(kind(N, Kind)), ensure_thing(N)
	),
	forall(member(P, Props), add(prop(N, P))),
	%  Inform's defaults: a door is closed; a container is open unless said.
	( Kind == door, \+ w(prop(N, open)) -> add(prop(N, closed)) ; true ),
	( Kind == door -> add(prop(N, openable)) ; true ).

%	A later word wins over an earlier one it contradicts: a sealed box is a
%	box (openable) which is not openable.
normalise_props(Ps0, Ps) :-
	foldl([P, In, Out]>>( ( negated(Pos, P) -> exclude(==(Pos), In, In1) ; In1 = In ),
			      ( negated(P, Neg) -> exclude(==(Neg), In1, In2) ; In2 = In1 ),
			      append(In2, [P], Out) ),
	      Ps0, [], Ps1),
	exclude(negative_only, Ps1, Ps).

%	"unopenable", "portable", "unlocked", "open" are the absence of a
%	property the library states positively.
negative_only(unopenable). negative_only(unlockable). negative_only(portable).
negative_only(unlocked). negative_only(open).

ensure_thing(N) :- ( w(room(N)) -> true ; w(region(N)) -> true ; add(thing(N)) ).
ensure_room(N) :- ( w(room(N)) -> true ; add(room(N)) ).

%	What holds something is a container, and what supports something a
%	supporter, unless it is a room or was declared otherwise — Inform
%	infers the same from "In the box is a banana".
place(N, in, H) :-
	retractall(w(in(N, _))), retractall(w(on(N, _))), add(in(N, H)),
	( w(room(H)) -> true ; w(kind(H, _)) -> true ; add(kind(H, container)), ensure_thing(H) ).
place(N, on, H) :-
	retractall(w(in(N, _))), retractall(w(on(N, _))), add(on(N, H)),
	( w(room(H)) -> true ; w(kind(H, _)) -> true ; add(kind(H, supporter)), ensure_thing(H) ).

		 /*******************************
		 *	     emitting		*
		 *******************************/

emit_le(File, Name, Text) :-
	with_output_to(string(Text), emit_le_(File, Name)).

emit_le_(File, Name) :-
	file_base_name(File, Base),
	format("the target language is: lps.~n~n", []),
	format("% ~w.le — generated from ~w by src/syntax/lps_inform.pl: Inform's~n", [Name, Base]),
	format("% assertions as a story on world.le. The rule register is reported, not~n", []),
	format("% translated; the Test-me script is the scenario.~n~n", []),
	( w(script(Cmds)) -> length(Cmds, NC) ; NC = 0 ),
	MaxT is 4 * NC + 4,
	format("the maximum time is ~w.~n~n", [MaxT]),
	atom_string(Name, NS), re_replace("_"/g, " ", NS, NameWords),
	format("the knowledge base ~w includes these resources: world, turns.~n~n", [NameWords]),
	%  Properties the library has no template for (`edible`, `transparent`)
	%  get one here, so the story states them and its own rules can read them.
	findall(P, ( w(prop(_, P)), \+ timeless_prop(P, _), \+ state_prop(P) ), Ps0),
	sort(Ps0, Ps),
	(   Ps == [] -> true
	;   format("the templates are:~n", []),
	    forall(member(P, Ps), format("    *a thing* is ~w.~n", [P])),
	    format("~n", [])
	),
	format("the knowledge base ~w includes:~n~n", [NameWords]),
	forall(w(room(R)), format("~w is a room.~n", [R])),
	forall(w(kind(N, K)), ( kind_sentence(N, K) )),
	forall(( w(prop(N, P)), timeless_prop(P, LE) ), format("~w is ~w.~n", [N, LE])),
	forall(( w(prop(N, P)), \+ timeless_prop(P, _), \+ state_prop(P) ), format("~w is ~w.~n", [N, P])),
	forall(w(key(L, K)), format("the key of ~w is ~w.~n", [L, K])),
	forall(w(map(D, F, T)), format("~w from ~w goes to ~w.~n", [D, F, T])),
	forall(door_link(Door, D, F, T), format("~w leads ~w from ~w to ~w.~n", [Door, D, F, T])),
	format("~n", []),
	findall(I, initial_fact(I), Is0), sort(Is0, Is),
	(   Is == [] -> format("initially the turn is 0.~n", [])
	;   format("initially the turn is 0", []),
	    forall(member(I, Is), format("~n    and ~w", [I])),
	    format(".~n", [])
	),
	(   w(script(Cmds)), Cmds \== []
	->  format("~nscenario one is:~n", []),
	    foldl(script_turn, Cmds, 1, _)
	;   true
	).

kind_sentence(N, person) :- !, format("~w is a person.~n", [N]).
kind_sentence(N, K) :- format("~w is a ~w.~n", [N, K]).

%	A door between two rooms: `X is east of the Hall and west of the Study`
%	gave door_side(X, hall, west) and door_side(X, study, east); the door
%	leads east from the hall to the study.
door_link(Door, Dir, From, To) :-
	w(door_side(Door, From, Back)), opposite(Back, Dir),
	w(door_side(Door, To, _)), To \== From, !.
door_link(Door, Dir, From, To) :-
	%  Only one side stated: the far side is unknown; a room called
	%  `beyond_<door>` stands for it.
	w(door_side(Door, From, Back)), opposite(Back, Dir),
	\+ ( w(door_side(Door, Other, _)), Other \== From ),
	atom_concat(beyond_, Door, To).

%	Properties that are fluents of the library, stated in `initially`.
state_prop(closed). state_prop(locked). state_prop(open). state_prop(unlocked).

timeless_prop(openable, openable).
timeless_prop(lockable, lockable).
timeless_prop(enterable, enterable).
timeless_prop(fixed, "fixed in place").

initial_fact(F) :- w(in(N, H)), format(atom(F), "~w is in ~w", [N, H]).
initial_fact(F) :- w(on(N, H)), format(atom(F), "~w is on ~w", [N, H]).
initial_fact(F) :- w(carried(N, P)), format(atom(F), "~w carries ~w", [P, N]).
initial_fact(F) :- w(worn(N, P)), format(atom(F), "~w wears ~w", [P, N]).
initial_fact(F) :- w(prop(N, closed)), format(atom(F), "~w is closed", [N]).
initial_fact(F) :- w(prop(N, locked)), format(atom(F), "~w is locked", [N]).
initial_fact("player is in ~w"-R) :- fail, w(room(R)).
initial_fact(F) :-
	%  The player starts in the first room, as Inform's does, unless placed.
	\+ w(in(player, _)), \+ w(on(player, _)),
	once(w(room(R))), R \== unnamed_room,
	format(atom(F), "player is in ~w", [R]).

%	A script line through the same short forms the player uses, as an LE
%	scenario sentence — or a comment, when the library has no such command.
script_turn(Cmd, K, K1) :-
	A is 4*K - 3, B is 4*K - 2, E is 4*K - 1, F is 4*K,
	(   command_sentence(Cmd, Sentence)
	->  format("    the turn begins from ~w to ~w.~n    ~w from ~w to ~w.~n    the turn ends from ~w to ~w.~n",
		   [A, B, Sentence, A, B, E, F])
	;   format("    % not translated: \"~w\" is not a command of the library~n", [Cmd])
	),
	K1 is K + 1.

command_sentence(Cmd, Sentence) :-
	normalize_space(string(C), Cmd), string_lower(C, L),
	split_string(L, " ", " ", Ws0), exclude(==(""), Ws0, Ws1),
	maplist([S, A]>>atom_string(A, S), Ws1, Ws2),
	exclude([W]>>memberchk(W, [the, a, an, some]), Ws2, Ws),
	cmd_form(Ws, Sentence).

cmd_form([W], "the command is to look") :- memberchk(W, [look, l]), !.
cmd_form([W], "the command is to take inventory") :- memberchk(W, [i, inv, inventory]), !.
cmd_form([W], "the command is to wait") :- memberchk(W, [z, wait]), !.
cmd_form([W], S) :- dir_word(W, D), !, format(string(S), "the command is to go ~w", [D]).
cmd_form([go, W], S) :- dir_word(W, D), !, format(string(S), "the command is to go ~w", [D]).
cmd_form([W|Ns], S) :- memberchk(W, [x, examine]), Ns \== [], !, noun(Ns, N), format(string(S), "the command is to examine ~w", [N]).
cmd_form([W|Ns], S) :- memberchk(W, [get, take]), Ns \== [], Ns \== [all], !, noun(Ns, N), format(string(S), "the command is to take ~w", [N]).
cmd_form([drop|Ns], S) :- Ns \== [], Ns \== [all], !, noun(Ns, N), format(string(S), "the command is to drop ~w", [N]).
cmd_form([open|Ns], S) :- Ns \== [], !, noun(Ns, N), format(string(S), "the command is to open ~w", [N]).
cmd_form([close|Ns], S) :- Ns \== [], !, noun(Ns, N), format(string(S), "the command is to close ~w", [N]).
cmd_form([enter|Ns], S) :- Ns \== [], !, noun(Ns, N), format(string(S), "the command is to enter ~w", [N]).
cmd_form([W], "the command is to exit") :- memberchk(W, [exit, out, leave]), !.
cmd_form(Ws, S) :- append(Xs, [P|Ys], Ws), memberchk(P, [in, into]), Xs = [put|Xs1], Xs1 \== [], Ys \== [], !,
	noun(Xs1, X), noun(Ys, Y), format(string(S), "the command is to put ~w into ~w", [X, Y]).
cmd_form(Ws, S) :- append(Xs, [P|Ys], Ws), memberchk(P, [on, onto]), Xs = [put|Xs1], Xs1 \== [], Ys \== [], !,
	noun(Xs1, X), noun(Ys, Y), format(string(S), "the command is to put ~w onto ~w", [X, Y]).
cmd_form(Ws, S) :- append([unlock|Xs], [with|Ys], Ws), Xs \== [], Ys \== [], !,
	noun(Xs, X), noun(Ys, Y), format(string(S), "the command is to unlock ~w with ~w", [X, Y]).
cmd_form(Ws, S) :- append([lock|Xs], [with|Ys], Ws), Xs \== [], Ys \== [], !,
	noun(Xs, X), noun(Ys, Y), format(string(S), "the command is to lock ~w with ~w", [X, Y]).

dir_word(n, north). dir_word(s, south). dir_word(e, east). dir_word(w, west).
dir_word(u, up). dir_word(d, down). dir_word(ne, northeast). dir_word(nw, northwest).
dir_word(se, southeast). dir_word(sw, southwest).
dir_word(D, D) :- memberchk(D, [north, south, east, west, up, down, northeast, northwest, southeast, southwest]).

%	The words of a noun phrase to the constant the assertions named — by
%	the same words, or by a suffix of them ("key" for silver_key), else the
%	words joined.
noun(Ws, N) :-
	atomic_list_concat(Ws, '_', Joined),
	(   known_object(Joined) -> N = Joined
	;   known_object(K), atom_concat(_, Joined, K), atom_concat(_, Suffix, K), atom_concat('_', Joined, Suffix) -> N = K
	;   N = Joined
	).

known_object(N) :- w(thing(N)) ; w(room(N)) ; w(kind(N, _)) ; w(in(N, _)) ; w(on(N, _)) ; w(carried(N, _)).

emit_companion(File, Text) :-
	file_base_name(File, Base),
	with_output_to(string(Text),
		       ( format("% descriptions from ~w, for the narrator (src/edges/lps_play.pl)~n", [Base]),
			 forall(w(desc(N, D)),
				( format("description(~q, ~q).~n", [N, D]) )) )).
