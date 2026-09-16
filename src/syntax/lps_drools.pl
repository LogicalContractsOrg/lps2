/* lps_drools.pl — DRL as a front end (M12d, §IV.2 and §IV.6).
 *
 * KELPS was framed as reconciling production systems with logic programming,
 * so this is the transpilation the theory was written for: `when … then …` is
 * a reactive rule, working memory is the state, and a rule that fires because
 * a fact appeared is an LPS cycle.
 *
 * The mapping (the *world reading*, at the end of this file: the facts are
 * states of the world, and what a rule does to working memory is an event in
 * it):
 *
 *   rule "R" when P1, P2 then RHS end
 *       →  if <P1 at T>, <P2 at T> then <events of RHS> from T.
 *   Type( field == v, x : other )
 *       →  the fluent type(…) with `v` in field's position and X in other's
 *          (a boolean field its own state: sprinkler_on(Room))
 *   not Type( … )                    →  not type(…) at T
 *   insert(new Type(a, b))           →  type_starts(a, b), initiating type(a, b)
 *   modify(v) { setOn(true) }        →  type_turns_on(…), initiating type_on(…)
 *   modify(v) { f = e }              →  type_f_becomes(…, e), updating type(…)
 *   retract(v) / delete(v)           →  type_ends(…), terminating type(…)
 *   declare Type f1 : t1 end         →  the field order for that type
 *   A() or B()                       →  one rule per alternative
 *   not Type( age > 65 )             →  not [type(…, Age) at T, Age > 65] at T
 *   R : Number(…) from accumulate( P, sum(v) )
 *                                    →  findall(V, [<P at T>], L) at T, sum_list(L, R)
 *   insertLogical(new Type(a))       →  type(a) at T if <conditions at T>
 *
 * §IV.1's boundary, stated rather than discovered: **the right-hand side of a
 * Drools rule is Java**, and Java is not transpiled. A statement this module
 * does not recognise is replaced by an *external action* — `java_leaf(Rule)`,
 * which the engine treats as an action with no causal law, so the run shows
 * where the Java would have run — and a diagnostic naming the rule and the
 * statement. A condition it does not recognise (`eval`, `forall`, `collect`,
 * `from`, a constraint it cannot read) leaves the whole rule out, with a
 * diagnostic: a rule read as something else would be worse than none. That
 * is the difference between a transpiler you can trust on a real rule base
 * and one that quietly drops half of it.
 *
 * Two semantic gaps that are reported, not papered over (§IV.5):
 *
 *   * **salience**. Drools resolves conflicts by an operational priority; LPS
 *     has no equivalent and is not supposed to. A rule with a salience gets a
 *     warning, and the priority is recorded in reactive_rule/3 where the
 *     engine can at least see it.
 *   * **truth maintenance** (`insertLogical`). A logically-inserted fact is
 *     retracted when its support goes away, which is an *intensional* fluent
 *     rather than a causal law, and that is how it is translated (with an
 *     informational diagnostic). Where the type's facts are also inserted,
 *     modified or deleted by a rule, or held by the working memory from the
 *     start, an intensional fluent cannot be the whole story: it is then an
 *     ordinary insert, with a warning that the fact is never withdrawn.
 */

:- module(lps_drools, [
	drl_to_internal/3,       % +File, -Terms, -Diags
	drl_to_internal/4,       % +File, +Options, -Terms, -Diags
	drl_reading/3,           % +File, +Options, -Reading
	drl_parse/3,             % +File, -Rules, -Declares
	drl_parse/4,             % +File, -Rules, -Declares, -Attributes
	drl_world_facts/3,       % +World, +Facts, -Fluents
	drl_driver_events/4,     % +World, +Op, +Fact, -Events
	drl_event_laws/3,        % +World, +Event, -Laws
	drl_templates/2,         % +World, -Templates
	drl_meaning/3,           % +World, +Name/Arity, -Meaning
	drl_initially_example/3  % +World, +Terms, -Text
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').

		 /*******************************
		 *	    tokenising		*
		 *******************************/

drl_text(File, Text) :-
	read_file_to_string(File, S, [encoding(utf8)]),
	string_codes(S, C0),
	strip_block_comments(C0, C1),
	strip_line_comments(C1, C2),
	string_codes(Text, C2).

strip_block_comments([], []).
strip_block_comments([0'/, 0'*|T], Out) :- !, skip_block(T, T1), strip_block_comments(T1, Out).
strip_block_comments([C|T], [C|Out]) :- strip_block_comments(T, Out).

skip_block([], []).
skip_block([0'*, 0'/|T], T) :- !.
skip_block([_|T], Out) :- skip_block(T, Out).

strip_line_comments([], []).
strip_line_comments([0'/, 0'/|T], Out) :- !, skip_line(T, T1), strip_line_comments(T1, Out).
strip_line_comments([C|T], [C|Out]) :- strip_line_comments(T, Out).

skip_line([], []).
skip_line([0'\n|T], [0'\n|T]) :- !.
skip_line([_|T], Out) :- skip_line(T, Out).

		 /*******************************
		 *	    parsing		*
		 *******************************/

%!	drl_parse(+File, -Rules, -Declares) is det.
%!	drl_parse(+File, -Rules, -Declares, -Attributes) is det.
%
%	Rules are rule(Name, Salience, Patterns, RHS, Line); Declares are
%	declare(Type, Fields); Attributes are attrs(Line, Name, [a(Attr,
%	Value), ...]), the attributes of the rule at Line (`no-loop`,
%	`agenda-group "g"`, ...: rule_attributes/2).
drl_parse(File, Rules, Declares) :-
	drl_parse(File, Rules, Declares, _).

drl_parse(File, Rules, Declares, Attributes) :-
	drl_text(File, Text),
	split_string(Text, "\n", "", Lines),
	parse_lines(Lines, 1, Rules, Declares, Attributes).

parse_lines([], _, [], [], []).
parse_lines([L|Ls], N, Rules, Declares, Attrs) :-
	normalize_space(string(T), L),
	N1 is N + 1,
	(   sub_string(T, 0, _, _, "rule ")
	->  rule_name(T, Name),
	    collect_until_end(Ls, Rest, Body0, N1, N2),
	    %  `rule RaiseAlarm when` (real DRL puts `when` on the rule's line)
	    %  (outside the quoted name: `rule "Raise the alarm when …"`)
	    unquoted(T, TU),
	    (   ( sub_string(TU, _, _, 0, " when") ; sub_string(TU, _, _, _, " when ") )
	    ->  Body = ["when"|Body0]
	    ;   Body = Body0
	    ),
	    rule_head_text(T, Head),
	    rule_of(Name, Head, Body, N, Rule, RAttrs),
	    parse_lines(Rest, N2, Rules0, Declares, Attrs0),
	    Rules = [Rule|Rules0], Attrs = [RAttrs|Attrs0]
	;   sub_string(T, 0, _, _, "declare ")
	->  declare_name(T, Type),
	    collect_until_end(Ls, Rest, Body, N1, N2),
	    fields_of(Body, Fields),
	    parse_lines(Rest, N2, Rules, Declares0, Attrs),
	    Declares = [declare(Type, Fields)|Declares0]
	;   parse_lines(Ls, N1, Rules, Declares, Attrs)
	).

collect_until_end([], [], [], N, N).
collect_until_end([L|Ls], Rest, Body, N, NOut) :-
	normalize_space(string(T), L),
	N1 is N + 1,
	(   T == "end"
	->  Rest = Ls, Body = [], NOut = N1
	;   collect_until_end(Ls, Rest, Body0, N1, NOut),
	    Body = [T|Body0]
	).

unquoted(T, U) :-
	split_string(T, "\"", "", Parts),
	findall(P, ( nth1(I, Parts, P), I mod 2 =:= 1 ), Out),
	atomic_list_concat(Out, ' ', U).

rule_name(T, Name) :-
	(   sub_string(T, B, _, _, "\""),
	    Start is B + 1,
	    sub_string(T, Start, _, _, R),
	    sub_string(R, E, _, _, "\"")
	->  sub_string(R, 0, E, _, S), atom_string(Name, S)
	;   split_string(T, " ", " ", ["rule", N0|_]), N0 \== "", N0 \== "when"
	->  atom_string(Name, N0)
	;   Name = unnamed
	).

%	What the rule's line has after its name, without a closing `when`: the
%	attributes written there (`rule "R" no-loop`).
rule_head_text(T, Head) :-
	(   sub_string(T, B, _, _, "\""), B1 is B + 1, sub_string(T, B1, _, 0, R),
	    sub_string(R, E, _, _, "\"")
	->  E1 is E + 1, sub_string(R, E1, _, 0, H0)
	;   split_string(T, " ", " ", ["rule", _|Ws])
	->  atomic_list_concat(Ws, ' ', H0)
	;   H0 = ""
	),
	normalize_space(string(H1), H0),
	(   H1 == "when" -> Head = ""
	;   string_concat(H2, " when", H1) -> Head = H2
	;   Head = H1
	).

declare_name(T, Type) :-
	split_string(T, " ", " ", Parts),
	( Parts = [_, S|_] -> string_lower(S, L), atom_string(Type, L) ; Type = unknown ).

fields_of(Lines, Fields) :-
	findall(F, ( member(L, Lines), split_string(L, ":", " ", [FS|_]),
		     FS \== "", string_lower(FS, LF), atom_string(F, LF) ), Fields).

%	when … then … — everything between is the condition, everything after
%	is the (Java) consequence; the lines before `when` (and the rule's own
%	line after its name) are its attributes.
rule_of(Name, Head, Body0, Line, rule(Name, Salience, Patterns, RHS, Line), attrs(Line, Name, Attrs)) :-
	split_keyword_lines(Body0, Body),
	(   nth0(I, Body, "when") -> length(Pre, I), append(Pre, _, Body) ; Pre = [] ),
	atomic_list_concat([Head|Pre], ' ', AttrText),
	rule_attributes(AttrText, Attrs),
	salience_of(Attrs, Salience),
	split_when_then(Body, When, Then),
	(   memberchk(a(extends, P), Attrs)
	->  attr_value_text(P, PT),
	    format(atom(Why), 'the rule extends ~w, whose conditions it inherits, and `extends` is not translated', [PT]),
	    Patterns = unsupported(Why)
	;   patterns_of(When, Patterns)
	),
	join_braces(Then, RHS).

%	`when Fire()` and `then insert(…)`: the keyword on a line of its own.
split_keyword_lines([], []).
split_keyword_lines([L|Ls], Out) :-
	(   member(K, ["when", "then"]), string_concat(K, R0, L),
	    sub_string(R0, 0, 1, _, " ")
	->  normalize_space(string(R), R0), Out = [K, R|Out1]
	;   Out = [L|Out1]
	),
	split_keyword_lines(Ls, Out1).

%	A `modify( x ) {` block over several lines is one statement.
join_braces([], []).
join_braces([L|Ls], [S|Rest]) :-
	brace_depth(L, 0, D),
	(   D > 0 -> join_block(Ls, D, L, S, Ls1) ; S = L, Ls1 = Ls ),
	join_braces(Ls1, Rest).

join_block([], _, Acc, Acc, []).
join_block([L|Ls], D0, Acc, S, Rest) :-
	atomic_list_concat([Acc, ' ', L], Acc1), atom_string(Acc1, AccS),
	brace_depth(L, D0, D),
	( D =< 0 -> S = AccS, Rest = Ls ; join_block(Ls, D, AccS, S, Rest) ).

brace_depth(S, D0, D) :-
	string_codes(S, Cs),
	foldl([C, In, Out]>>( C =:= 0'{ -> Out is In + 1 ; C =:= 0'} -> Out is In - 1 ; Out = In ), Cs, D0, D).

salience_of(Attrs, S) :-
	( memberchk(a(salience, V), Attrs), number(V) -> S = V ; S = 0 ).

/* Rule attributes: `salience 10`, `no-loop`, `no-loop true`, `agenda-group
   "g"`, `timer (int: 30s)`, `@Name(...)`, separated by spaces or commas —
   a(Attr, Value), Attr the attribute's name as written (an atom, `no-loop`)
   and Value true, false, a number, str(Text), expr(Text) (parenthesised) or
   none (a boolean attribute written without its value).
*/
rule_attributes(Text, Attrs) :-
	string_codes(Text, Cs),
	attrs_(Cs, Attrs).

attrs_(Cs0, Attrs) :-
	skip_sep(Cs0, Cs),
	(   Cs == []
	->  Attrs = []
	;   Cs = [0'@|Cs1]
	->  ident_prefix(Cs1, NCs, Cs2), skip_ws(Cs2, Cs3),
	    (   Cs3 = [0'(|Cs4]
	    ->  close_paren(Cs4, VCs, Cs5), string_codes(V, VCs), Val = expr(V)
	    ;   Val = none, Cs5 = Cs2
	    ),
	    atom_codes(N0, NCs), atom_concat('@', N0, N),
	    Attrs = [a(N, Val)|More], attrs_(Cs5, More)
	;   Cs = [C|_], code_type(C, alpha)
	->  attr_name(Cs, NCs, Cs1), atom_codes(N, NCs),
	    skip_ws(Cs1, Cs2),
	    attr_value(N, Cs2, Val, Cs3),
	    Attrs = [a(N, Val)|More], attrs_(Cs3, More)
	;   word_codes(Cs, WCs, Cs1), string_codes(W, WCs),
	    Attrs = [a('?', str(W))|More], attrs_(Cs1, More)
	).

skip_sep([C|Cs], Out) :- ( code_type(C, space) ; C =:= 0', ), !, skip_sep(Cs, Out).
skip_sep(Cs, Cs).

skip_ws([C|Cs], Out) :- code_type(C, space), !, skip_ws(Cs, Out).
skip_ws(Cs, Cs).

attr_name([C|Cs], [C|Ns], Rest) :- ( code_type(C, csym) ; C =:= 0'- ), !, attr_name(Cs, Ns, Rest).
attr_name(Cs, [], Cs).

word_codes([C|Cs], [C|Ws], Rest) :- \+ code_type(C, space), C =\= 0',, !, word_codes(Cs, Ws, Rest).
word_codes(Cs, [], Cs).

bool_attribute(A) :- memberchk(A, ['no-loop', 'lock-on-active', 'auto-focus', enabled]).

known_attribute(A) :-
	memberchk(A, [salience, enabled, 'date-effective', 'date-expires', 'no-loop', 'agenda-group',
		      'activation-group', 'ruleflow-group', duration, timer, calendars, 'auto-focus',
		      'lock-on-active', dialect, extends]).

attr_value(_, [Q|Cs], str(S), Rest) :-
	( Q =:= 0'" ; Q =:= 0'\' ), !,
	string_end(Cs, Q, SCs, Rest), string_codes(S, SCs).
attr_value(_, [0'(|Cs], expr(S), Rest) :- !,
	close_paren(Cs, SCs, Rest0), string_codes(S0, SCs), normalize_space(string(S), S0),
	Rest = Rest0.
attr_value(N, Cs, Val, Rest) :-
	word_codes_value(Cs, WCs, Rest0),
	atom_codes(W, WCs),
	(   WCs == [] -> Val = none, Rest = Cs
	;   memberchk(W, [true, (false)]) -> Val = W, Rest = Rest0
	;   atom_number(W, Num) -> Val = Num, Rest = Rest0
	;   ( bool_attribute(N) ; known_attribute(W) ) -> Val = none, Rest = Cs
	;   atom_string(W, WS), Val = str(WS), Rest = Rest0
	).

word_codes_value([C|Cs], [C|Ws], Rest) :- \+ code_type(C, space), C =\= 0',, !, word_codes_value(Cs, Ws, Rest).
word_codes_value(Cs, [], Cs).

string_end([], _, [], []).
string_end([0'\\, C|Cs], Q, [0'\\, C|S], Rest) :- !, string_end(Cs, Q, S, Rest).
string_end([C|Cs], Q, S, Rest) :-
	( C =:= Q -> S = [], Rest = Cs ; S = [C|S1], string_end(Cs, Q, S1, Rest) ).

%	The codes up to the parenthesis that closes one already open (outside
%	strings), and what follows it.
close_paren(Cs, In, Rest) :- close_paren_(Cs, 1, 0, In, Rest).

close_paren_([], _, _, [], []).
close_paren_([C|Cs], D, Q, In, Rest) :-
	(   Q =:= 0, C =:= 0'), D =:= 1
	->  In = [], Rest = Cs
	;   Q =:= 0, ( C =:= 0'" ; C =:= 0'\' )
	->  In = [C|In1], close_paren_(Cs, D, C, In1, Rest)
	;   Q =\= 0, C =:= 0'\\, Cs = [C2|Cs2]
	->  In = [C, C2|In1], close_paren_(Cs2, D, Q, In1, Rest)
	;   Q =\= 0, C =:= Q
	->  In = [C|In1], close_paren_(Cs, D, 0, In1, Rest)
	;   Q =:= 0, C =:= 0'(
	->  D1 is D + 1, In = [C|In1], close_paren_(Cs, D1, Q, In1, Rest)
	;   Q =:= 0, C =:= 0')
	->  D1 is D - 1, In = [C|In1], close_paren_(Cs, D1, Q, In1, Rest)
	;   In = [C|In1], close_paren_(Cs, D, Q, In1, Rest)
	).

attr_value_text(str(S), T) :- !, format(atom(T), '"~w"', [S]).
attr_value_text(expr(S), T) :- !, format(atom(T), '(~w)', [S]).
attr_value_text(V, V).

split_when_then(Body, When, Then) :-
	(   nth0(I, Body, "when")
	->  J is I + 1, length(Pre, J), append(Pre, Rest, Body),
	    (	nth0(K, Rest, "then")
	    ->	length(When, K), append(When, [_|Then], Rest)
	    ;	When = Rest, Then = []
	    )
	;   When = [], Then = Body
	).

/* The conditions of a rule: a list of patterns, `or(Alternatives)` (a list
   of such lists) when the rule has `or` between patterns, or
   `unsupported(Why)` when a condition is one this reader does not
   translate. A pattern is pattern(Kind, Var, Type, Constraints) — `Var :
   Type( constraints )`, with `not` and `exists` — and an accumulate is
   acc(ResultVar, Function, ArgVar, InnerPatterns, [Op-Value, ...]).
 *
 * DRL separates patterns by *line*, not by comma — the commas inside the
 * parentheses separate a pattern's own constraints. So lines are joined only
 * while their parentheses are unbalanced, which is how a pattern wrapped over
 * three lines stays one pattern.
 *
 * `or` between patterns is what Drools compiles into one subrule per
 * alternative, and so is the reading: the conditions are put in disjunctive
 * form, one alternative per LPS rule. `||` between the constraints of one
 * pattern is the same thing, one level down. `not( A or B )` is `not A`
 * and `not B`. What has no faithful reading here — `forall`, `eval`,
 * `collect`, `from`, `average`, `not` over a conjunction, a constraint this
 * reader does not know — makes the rule `unsupported`: it is reported and
 * left out, never read as something else.
 */
patterns_of(Lines, Body) :-
	join_wrapped(Lines, Chunks0),
	findall(C, ( member(X, Chunks0), normalize_space(atom(C), X), C \== '',
		     C \== 'and' ), Chunks1),
	join_infix_lines(Chunks1, Chunks),
	catch(( maplist(chunk_alternatives, Chunks, PerChunk),
		findall(Ps, ( cross_product(PerChunk, Pss), append(Pss, Ps) ), Alts),
		( Alts = [One] -> Body = One ; Body = or(Alts) ) ),
	      drl_unsupported(Why),
	      Body = unsupported(Why)).

%	`A()` on one line and `or B()` on the next are one condition.
join_infix_lines([], []).
join_infix_lines([A, B|Cs], Out) :-
	(   member(W, ['or ', 'and ', '||', '&&']), sub_atom(B, 0, _, _, W)
	;   member(W, [' or', ' and', '||', '&&']), sub_atom(A, _, _, 0, W)
	), !,
	atomic_list_concat([A, ' ', B], AB),
	join_infix_lines([AB|Cs], Out).
join_infix_lines([C|Cs], [C|Out]) :- join_infix_lines(Cs, Out).

cross_product([], []).
cross_product([Alts|Rest], [X|Xs]) :- member(X, Alts), cross_product(Rest, Xs).

unsupported(Fmt, Args) :-
	format(atom(M), Fmt, Args),
	throw(drl_unsupported(M)).

join_wrapped([], []).
join_wrapped([L|Ls], [Chunk|Rest]) :-
	depth_of(L, 0, D),
	(   D =:= 0
	->  Chunk = L, Ls1 = Ls
	;   join_more(Ls, D, L, Chunk, Ls1)
	),
	join_wrapped(Ls1, Rest).

join_more([], _, Acc, Acc, []).
join_more([L|Ls], D0, Acc, Chunk, Rest) :-
	atomic_list_concat([Acc, ' ', L], Acc1),
	depth_of(L, D0, D),
	( D =:= 0 -> Chunk = Acc1, Rest = Ls ; join_more(Ls, D, Acc1, Chunk, Rest) ).

depth_of(S, D0, D) :-
	atom_string(A, S), atom_codes(A, Cs),
	foldl([C, In, Out]>>( C =:= 0'( -> Out is In + 1
			    ; C =:= 0') -> Out is In - 1
			    ; Out = In ), Cs, D0, D).

%	Split S at the separators that are outside parentheses and strings.
top_split(S0, Seps, Parts) :-
	atom_string(S0, S),
	string_codes(S, Cs),
	findall(SC, ( member(Sep, Seps), string_codes(Sep, SC) ), SepCs),
	top_split_(Cs, 0, (false), SepCs, [], Parts0),
	findall(P, ( member(PC, Parts0), string_codes(P0, PC), normalize_space(string(P), P0) ), Parts).

top_split_([], _, _, _, Acc, [Part]) :- reverse(Acc, Part).
top_split_([C|Cs], D, Q, Seps, Acc, Parts) :-
	(   Q == (false), D =:= 0, member(Sep, Seps), append(Sep, Rest, [C|Cs])
	->  reverse(Acc, Part), Parts = [Part|More],
	    top_split_(Rest, D, Q, Seps, [], More)
	;   C =:= 0'\"
	->  ( Q == (false) -> Q1 = true ; Q1 = (false) ),
	    top_split_(Cs, D, Q1, Seps, [C|Acc], Parts)
	;   Q == (false), C =:= 0'(
	->  D1 is D + 1, top_split_(Cs, D1, Q, Seps, [C|Acc], Parts)
	;   Q == (false), C =:= 0')
	->  D1 is D - 1, top_split_(Cs, D1, Q, Seps, [C|Acc], Parts)
	;   top_split_(Cs, D, Q, Seps, [C|Acc], Parts)
	).

%	`( … )` around the whole of S.
outer_parens(S0, In) :-
	atom_string(S0, S),
	sub_string(S, 0, 1, _, "("), sub_string(S, _, 1, 0, ")"),
	sub_string(S, 1, _, 1, In0), balanced_parens(In0),
	normalize_space(string(In), In0).

%!	chunk_alternatives(+Chunk, -Alternatives) is det.
%
%	One condition of a rule as a list of alternatives, each a list of
%	patterns (and accumulates) that must all hold. Throws
%	drl_unsupported(Why).
chunk_alternatives(Chunk, Alts) :-
	atom_string(Chunk, S0), strip_semicolon(S0, S),
	(   S == ""
	->  Alts = [[]]
	;   top_split(S, [" or ", "||"], Parts), Parts = [_, _|_]
	->  maplist(chunk_alternatives, Parts, PAlts), append(PAlts, Alts)
	;   top_split(S, [" and ", "&&"], Parts), Parts = [_, _|_]
	->  maplist(chunk_alternatives, Parts, PAlts),
	    findall(Ps, ( cross_product(PAlts, Pss), append(Pss, Ps) ), Alts)
	;   outer_parens(S, In)
	->  (   ( sub_string(In, 0, _, _, "or ") ; sub_string(In, 0, _, _, "and ") )
	    ->  unsupported('the prefix form `~w` of a condition', [S])
	    ;   chunk_alternatives(In, Alts)
	    )
	;   quantified(S, "not", In)
	->  chunk_alternatives(In, InAlts),
	    (   forall(member(A, InAlts), A = [pattern(pos, _, _, _)])
	    ->  findall(pattern(neg, V, T, Cs), member([pattern(pos, V, T, Cs)], InAlts), Negs),
		Alts = [Negs]
	    ;   unsupported('`~w`: `not` over more than one pattern (or over an accumulate) has no LPS reading here', [S])
	    )
	;   quantified(S, "exists", In)
	->  chunk_alternatives(In, InAlts),
	    (   forall(( member(A, InAlts), member(P, A) ), P = pattern(pos, _, _, _))
	    ->  Alts = InAlts
	    ;   unsupported('`~w`: `exists` over a negation or an accumulate has no LPS reading here', [S])
	    )
	;   quantified(S, "forall", _)
	->  unsupported('`~w`: `forall` is not translated', [S])
	;   sub_string(S, _, _, _, "accumulate")
	->  accumulate_chunk(S, Acc), Alts = [[Acc]]
	;   member(W, ["collect", " from ", "eval", "entry-point", "over window", "window:"]),
	    sub_string(S, _, _, _, W)
	->  normalize_space(atom(WA), W),
	    unsupported('`~w`: `~w` is not translated', [S, WA])
	;   pattern_of(S, pattern(Kind, Var, Type, CAlts))
	->  findall([pattern(Kind, Var, Type, Cs)], member(Cs, CAlts), Alts)
	;   unsupported('`~w` is not a pattern this reader understands', [S])
	).

%	`Type( constraints )` or `Var : Type( constraints )`, the constraints
%	as alternatives (`||`).
pattern_of(S1, pattern(pos, Var, Type, CAlts)) :-
	(   sub_string(S1, B, 1, _, ":"), sub_string(S1, 0, B, _, V0),
	    normalize_space(string(VS), V0), VS \== "", \+ sub_string(VS, _, _, _, "("),
	    \+ sub_string(VS, _, _, _, " ")
	->  atom_string(Var, VS), Bp is B + 1, sub_string(S1, Bp, _, 0, S3),
	    normalize_space(string(S2), S3)
	;   Var = '', S2 = S1
	),
	sub_string(S2, P, 1, _, "("), !,
	sub_string(S2, _, 1, 0, ")"),
	sub_string(S2, 0, P, _, T0), normalize_space(string(TS), T0),
	TS \== "", \+ sub_string(TS, _, _, _, " "),
	atomic_list_concat(TParts, '.', TS), last(TParts, TLast),
	string_lower(TLast, TL), atom_string(Type, TL),
	Pp is P + 1, sub_string(S2, Pp, _, 1, Inner0),
	balanced_parens(Inner0),
	normalize_space(string(Inner), Inner0),
	constraints_of(Inner, CAlts).

%	`not Fire()`, `not( Hope() )`, `exists Fire()`, `exists( Politician( … ) )`.
quantified(S, Word, Rest) :-
	string_concat(Word, R0, S),
	normalize_space(string(R1), R0),
	(   sub_string(R0, 0, 1, _, " ") ; sub_string(R0, 0, 1, _, "(") ), !,
	(   sub_string(R1, 0, 1, _, "("), sub_string(R1, _, 1, 0, ")"),
	    sub_string(R1, 1, _, 1, In), balanced_parens(In)
	->  normalize_space(string(Rest), In)
	;   Rest = R1
	).

balanced_parens(S) :- string_codes(S, Cs), balanced(Cs, 0).
balanced([], 0).
balanced([C|Cs], D) :- ( C =:= 0'( -> D1 is D + 1 ; C =:= 0') -> D1 is D - 1, D1 >= 0 ; D1 = D ), balanced(Cs, D1).

strip_semicolon(S0, S) :- normalize_space(string(S1), S0), ( string_concat(S, ";", S1) -> true ; S = S1 ).

%	A pattern's constraints, as alternatives: [[C1, C2, ...], ...] — one
%	list unless `||` is between them.
constraints_of("", [[]]) :- !.
constraints_of(S, CAlts) :-
	top_split(S, [",", "&&"], Parts0),
	exclude(==(""), Parts0, Parts),
	maplist(constraint_alternatives, Parts, PerPart),
	findall(Cs, ( cross_product(PerPart, Css), append(Css, Cs) ), CAlts).

constraint_alternatives(P, Alts) :-
	(   top_split(P, ["||"], Ors), Ors = [_, _|_]
	->  findall(Cs, ( member(O, Ors), constraints_of(O, OAlts), member(Cs, OAlts) ), Alts)
	;   outer_parens(P, In)
	->  constraints_of(In, Alts)
	;   atom_string(A, P), constraint_of(A, C),
	    (   C = other(_)
	    ->  unsupported('the constraint `~w` is not one this reader understands', [P])
	    ;   constraint_field(C, F), \+ identifier(F)
	    ->  unsupported('the constraint `~w` is not on a field of the fact', [P])
	    ;   constraint_field(C, this)
	    ->  unsupported('the constraint `~w` is on the fact itself (`this`), which is not translated', [P])
	    ;   Alts = [[C]]
	    )
	).

/* `accumulate`, in both of its forms:

     $total : Number( intValue > 100 ) from accumulate( Order( $v : value ), sum( $v ) )
     accumulate( Order( $v : value ); $total : sum( $v ); $total > 100 )

   is an aggregate over the state, which LPS has: `findall` inside `holds`
   and a reduction (sum_list, length, min_list, max_list) — the same form
   Logical English's `is the sum of each … such that` compiles to. `average`
   (LPS has no mean) and custom accumulate code (init/action/result) are not
   translated.
*/
accumulate_chunk(S, acc(RVar, Fn, AVar, Inner, RCmps)) :-
	sub_string(S, B, _, _, "accumulate"), !,
	sub_string(S, 0, B, _, Pre0), normalize_space(string(Pre), Pre0),
	B1 is B + 10, sub_string(S, B1, _, 0, Post0), normalize_space(string(Post), Post0),
	(   outer_parens(Post, Args) -> true
	;   unsupported('`~w`: an accumulate this reader cannot take apart', [S])
	),
	(   Pre == "", top_split(Args, [";"], [InnerS, FnS|Rest])
	->  fn_binding(S, FnS, RVar, Fn, AVar),
	    maplist(result_constraint(S, RVar), Rest, RCmps)
	;   string_concat(RP0, "from", Pre), top_split(Args, [","], Parts),
	    append(InnerParts, [FnS], Parts), InnerParts \== []
	->  atomic_list_concat(InnerParts, ', ', InnerS),
	    fn_call(S, FnS, Fn, AVar),
	    normalize_space(string(RP), RP0),
	    result_pattern(S, RP, RVar, RCmps)
	;   unsupported('`~w`: an accumulate this reader cannot take apart (custom init/action/result code is not translated)', [S])
	),
	(   catch(chunk_alternatives(InnerS, [Inner]), drl_unsupported(_), fail),
	    forall(member(P, Inner), P = pattern(_, _, _, _))
	->  true
	;   unsupported('`~w`: the patterns an accumulate ranges over must be plain patterns, with no `or`', [S])
	),
	(   ( Fn == count ; member(pattern(_, _, _, Cs), Inner), memberchk(bind(_, AVar), Cs) )
	->  true
	;   unsupported('`~w`: the value an accumulate adds up must be bound in its pattern (`$v : field`)', [S])
	).

fn_binding(S, FnS, RVar, Fn, AVar) :-
	(   sub_string(FnS, B, 1, _, ":"), sub_string(FnS, 0, B, _, V0), \+ sub_string(V0, _, _, _, "(")
	->  normalize_space(atom(RVar), V0), B1 is B + 1, sub_string(FnS, B1, _, 0, Call),
	    fn_call(S, Call, Fn, AVar)
	;   unsupported('`~w`: an accumulate whose result is not bound (`$total : sum( $v )`)', [S])
	).

fn_call(S, Call0, Fn, AVar) :-
	normalize_space(string(Call), Call0),
	(   sub_string(Call, P, 1, _, "("), sub_string(Call, _, 1, 0, ")")
	->  sub_string(Call, 0, P, _, F0), normalize_space(atom(F1), F0), downcase_atom(F1, F),
	    P1 is P + 1, sub_string(Call, P1, _, 1, A0), normalize_space(atom(AVar), A0),
	    (   memberchk(F, [sum, count, min, max]) -> Fn = F
	    ;   F == average
	    ->  unsupported('`~w`: `average` is not translated (LPS has no mean of a list)', [S])
	    ;   unsupported('`~w`: the accumulate function `~w` is not translated', [S, F])
	    )
	;   unsupported('`~w`: an accumulate this reader cannot take apart', [S])
	).

%	`$total > 100` after the function (the modern form).
result_constraint(S, RVar, CS, Op-V) :-
	atom_string(CA, CS), constraint_of(CA, C), downcase_atom(RVar, RV),
	(   C = cmp(Op, RV, V) -> true
	;   C = eq(RV, V) -> Op = '=='
	;   unsupported('`~w`: the accumulate constraint `~w` is not translated', [S, CS])
	).

%	`$total : Number( intValue > 100 )` before `from` (the classic form).
result_pattern(S, RP, RVar, RCmps) :-
	(   sub_string(RP, B, 1, _, ":"), sub_string(RP, 0, B, _, V0), \+ sub_string(V0, _, _, _, "(")
	->  normalize_space(atom(RVar), V0), B1 is B + 1, sub_string(RP, B1, _, 0, P0)
	;   flag(drl_accumulate, N, N + 1), format(atom(RVar), '$accumulate_~w', [N]), P0 = RP
	),
	normalize_space(string(P), P0),
	(   pattern_of(P, pattern(pos, '', _, [Cs]))
	->  maplist(result_value_constraint(S), Cs, RCmps)
	;   unsupported('`~w`: the result of an accumulate must be a plain `Number( … )` pattern', [S])
	).

result_value_constraint(S, C, Op-V) :-
	(   C = cmp(Op, F, V), value_field(F) -> true
	;   C = eq(F, V), value_field(F) -> Op = '=='
	;   unsupported('`~w`: a constraint on the result of an accumulate other than a comparison of its value', [S])
	).

value_field(F) :- memberchk(F, [intvalue, longvalue, doublevalue, floatvalue, this]).

constraint_of(A, cmp(Op, Field, Value)) :-
	member(Op, ['!=', '>=', '<=', '>', '<']),
	sub_atom(A, B, L, _, Op), \+ ( Op == '>' ; Op == '<' ), !,
	sub_atom(A, 0, B, _, F0), Bp is B + L, sub_atom(A, Bp, _, 0, V0),
	clean_field(F0, Field), clean_value(V0, Value).
constraint_of(A, cmp(Op, Field, Value)) :-
	member(Op, ['>', '<']),
	sub_atom(A, B, 1, _, Op), \+ sub_atom(A, B, 2, _, '>='), \+ sub_atom(A, B, 2, _, '<='), !,
	sub_atom(A, 0, B, _, F0), Bp is B + 1, sub_atom(A, Bp, _, 0, V0),
	clean_field(F0, Field), clean_value(V0, Value).
constraint_of(A, eq(Field, Value)) :-
	sub_atom(A, B, 2, _, '=='), !,
	sub_atom(A, 0, B, _, F0), Bp is B + 2, sub_atom(A, Bp, _, 0, V0),
	clean_field(F0, Field), clean_value(V0, Value).
constraint_of(A, bind(Field, Var)) :-
	sub_atom(A, B, 1, _, ':'), !,
	sub_atom(A, 0, B, _, V0), Bp is B + 1, sub_atom(A, Bp, _, 0, F0),
	clean_field(F0, Field), clean_var(V0, Var),
	identifier(Field), identifier(Var).
constraint_of(A, other(A)).

identifier(A) :- atom_codes(A, [C|Cs]), ( code_type(C, csymf) ; C == 0'$ ), forall(member(X, Cs), code_type(X, csym)).

clean_field(A, F) :- normalize_space(atom(N), A), downcase_atom(N, D), F = D.
clean_var(A, V) :- normalize_space(atom(N), A), V = N.

clean_value(A, V) :-
	normalize_space(atom(N), A),
	(   atom_number(N, Num) -> V = Num
	;   sub_atom(N, 0, 1, _, '"')
	->  sub_atom(N, 1, _, 1, S), V = S
	;   sub_atom(N, B, 1, _, '.'), B > 0, atomic_list_concat([Obj, Fld], '.', N),
	    sub_atom(Obj, 0, 1, _, O1), ( char_type(O1, lower) ; O1 == '$' )
	->  downcase_atom(Fld, F1), V = ref(Obj, F1)      % `s.room`: the room of s
	;   sub_atom(N, B, 1, _, '.'), sub_atom(N, _, _, 0, Last), B > 0
	->  atomic_list_concat(Parts, '.', N), last(Parts, LastPart),
	    downcase_atom(LastPart, V), ignore(Last = Last)
	;   sub_atom(N, 0, 1, _, '$')
	->  V = N                                            % a variable: its case is its name
	;   downcase_atom(N, V)
	).

/* A value in the Java of a consequence — a constructor's argument, a
   setter's, the right of `f = …` in a modify block:

     - a literal, a variable, `s.room`, `Tier.GOLD`: as clean_value/2;
     - an accessor of a bound variable, `$p.getName()`, `$p.isOn()`,
       `$p.name`, and `$total.intValue()` (and the other xValue()s, a
       number itself), and arithmetic over those and numbers (`+ - * / %`,
       parentheses, unary minus): jexpr(Expr, Text), Expr over ref(Var,
       Field), xvalue(E), variable names and numbers — computed when the
       rule fires (resolve_value/6);
     - anything else (another method call, `new`, a string concatenation,
       a conditional, a cast): untranslatable(Text). The statement it is in
       is then Java, not a change (rhs_actions/7): a value the reader cannot
       compute is never written as a constant.
*/
java_value(S0, V) :-
	normalize_space(string(S), S0),
	(   S == ""
	->  V = untranslatable(S)
	;   plain_value(S)
	->  clean_value(S, V)
	;   string_codes(S, Cs), catch(java_tokens(Cs, Ts), _, fail),
	    phrase(jexpr(E), Ts)
	->  V = jexpr(E, S)
	;   V = untranslatable(S)
	).

%	A literal, a name or `a.b`: no operator, no call.
plain_value(S) :-
	(   sub_string(S, 0, 1, _, "\""), sub_string(S, _, 1, 0, "\""), string_length(S, L), L >= 2
	->  sub_string(S, 1, _, 1, In), \+ sub_string(In, _, _, _, "\"")
	;   number_string(_, S)
	->  true
	;   string_codes(S, Cs),
	    forall(member(C, Cs), ( code_type(C, csym) ; C =:= 0'$ ; C =:= 0'. )),
	    Cs = [C0|_], \+ code_type(C0, digit)
	).

java_tokens([], []).
java_tokens([C|Cs], Ts) :-
	(   code_type(C, space)
	->  java_tokens(Cs, Ts)
	;   code_type(C, digit)
	->  number_codes_([C|Cs], NCs, Rest), number_codes(N, NCs),
	    Ts = [num(N)|Ts1], java_tokens(Rest, Ts1)
	;   ( code_type(C, csymf) ; C =:= 0'$ )
	->  ident_prefix_([C|Cs], ICs, Rest0), atom_codes(Id, ICs), Id \== new,
	    selectors(Rest0, Sel, Rest),
	    Ts = [prim([id(Id)|Sel])|Ts1], java_tokens(Rest, Ts1)
	;   C =:= 0'( -> Ts = [lp|Ts1], java_tokens(Cs, Ts1)
	;   C =:= 0') -> Ts = [rp|Ts1], java_tokens(Cs, Ts1)
	;   memberchk(C-Op, [0'+ - (+), 0'- - (-), 0'* - (*), 0'/ - (/), 0'% - mod])
	->  Ts = [op(Op)|Ts1], java_tokens(Cs, Ts1)
	).

number_codes_([C|Cs], [C|Ns], Rest) :- ( code_type(C, digit) ; C =:= 0'. ), !, number_codes_(Cs, Ns, Rest).
number_codes_([C|Cs], [], Cs) :- memberchk(C, `lLdDfF`), !.
number_codes_(Cs, [], Cs).

ident_prefix_([C|Cs], [C|Is], After) :- ( code_type(C, csym) ; C =:= 0'$ ), !, ident_prefix_(Cs, Is, After).
ident_prefix_(Cs, [], Cs).

%	`.name` and `.name()` after a name (a call with arguments is not read).
selectors(Cs0, Sel, Rest) :-
	skip_ws(Cs0, Cs),
	(   Cs = [0'.|Cs1], skip_ws(Cs1, Cs2), Cs2 = [C|_], code_type(C, csymf)
	->  ident_prefix_(Cs2, ICs, Cs3), atom_codes(Id, ICs), skip_ws(Cs3, Cs4),
	    (   Cs4 = [0'(|Cs5], skip_ws(Cs5, [0')|Cs6])
	    ->  Sel = [call(Id)|Sel1], selectors(Cs6, Sel1, Rest)
	    ;   Cs4 = [0'(|_]
	    ->  fail
	    ;   Sel = [id(Id)|Sel1], selectors(Cs3, Sel1, Rest)
	    )
	;   Sel = [], Rest = Cs0
	).

jexpr(E) --> jterm(T), jexpr_rest(T, E).
jexpr_rest(Acc, E) --> [op(Op)], { memberchk(Op, [+, -]) }, !, jterm(T), { A =.. [Op, Acc, T] }, jexpr_rest(A, E).
jexpr_rest(E, E) --> [].
jterm(T) --> jfactor(F), jterm_rest(F, T).
jterm_rest(Acc, T) --> [op(Op)], { memberchk(Op, [*, /, mod]) }, !, jfactor(F), { A =.. [Op, Acc, F] }, jterm_rest(A, T).
jterm_rest(T, T) --> [].
jfactor(-(F)) --> [op(-)], !, jfactor(F).
jfactor(E) --> [lp], !, jexpr(E), [rp].
jfactor(N) --> [num(N)], !.
jfactor(E) --> [prim(Sel)], { prim_expr(Sel, E) }.

%	`$x`, `$p.name`, `$p.getName()`, `$p.isOn()`, `$t.intValue()`,
%	`$p.getAge().intValue()`.
prim_expr([id(X)], X).
prim_expr([id(O), id(F)], ref(O, LF)) :- var_like(O), downcase_atom(F, LF).
prim_expr([id(O), call(G)], ref(O, F)) :- var_like(O), getter_field(G, F).
prim_expr([id(X), call(M)], xvalue(X)) :- xvalue_method(M).
prim_expr(Sel, xvalue(E)) :-
	append(Sel0, [call(M)], Sel), Sel0 = [_, _|_], xvalue_method(M),
	prim_expr(Sel0, E), E = ref(_, _).

var_like(O) :- sub_atom(O, 0, 1, _, C), ( C == '$' ; char_type(C, lower) ).

getter_field(G, F) :-
	( atom_concat(get, F0, G) ; atom_concat(is, F0, G) ),
	F0 \== '', sub_atom(F0, 0, 1, _, C1), char_type(C1, upper), !,
	downcase_atom(F0, F).

xvalue_method(M) :- memberchk(M, [intValue, longValue, doubleValue, floatValue, shortValue, byteValue]).

%!	resolve_value(+Value, +Order, +Map, -Term, -Goals0, ?Goals) is semidet.
%
%	A value of a consequence as a term of the rule: a variable of the rule
%	for a name it binds, the slot of `s.room`, and for an expression a new
%	variable with the goal `V is Expr` (Goals0-Goals, a difference list:
%	no findall/3, whose copies would share nothing with the rule). Fails
%	for a value that cannot be computed from the rule's conditions.
resolve_value(V, _, _, V, Gs, Gs) :- var(V), !.
resolve_value(untranslatable(_), _, _, _, _, _) :- !, fail.
resolve_value(jexpr(E, _), Order, Map, R, Gs0, Gs) :- !,
	resolve_expr(E, Order, Map, E1),
	(   ( var(E1) ; atomic(E1) ) -> R = E1, Gs0 = Gs
	;   Gs0 = [R is E1|Gs]
	).
resolve_value(ref(O, F), Order, Map, R, Gs, Gs) :- !,
	ref_slot(O, F, Order, Map, R).
resolve_value(V, _, Map, R, Gs, Gs) :-
	( atom(V), memberchk(V-X, Map) -> R = X ; R = V ).

resolve_expr(N, _, _, N) :- number(N), !.
resolve_expr(X, _, Map, V) :- atom(X), !, memberchk(X-V, Map).
resolve_expr(ref(O, F), Order, Map, V) :- !, ref_slot(O, F, Order, Map, V).
resolve_expr(xvalue(E), Order, Map, V) :- !, resolve_expr(E, Order, Map, V).
resolve_expr(E, Order, Map, E1) :-
	compound(E), E =.. [Op|As], memberchk(Op, [+, -, *, /, mod]),
	resolve_exprs(As, Order, Map, Bs),      % (no yall: it copies the map)
	E1 =.. [Op|Bs].

resolve_exprs([], _, _, []).
resolve_exprs([A|As], Order, Map, [B|Bs]) :- resolve_expr(A, Order, Map, B), resolve_exprs(As, Order, Map, Bs).

resolve_values([], _, _, [], Gs, Gs).
resolve_values([V|Vs], Order, Map, [R|Rs], Gs0, Gs) :-
	resolve_value(V, Order, Map, R, Gs0, Gs1),
	resolve_values(Vs, Order, Map, Rs, Gs1, Gs).

%	The text of a value, for a diagnostic.
value_text(untranslatable(S), S) :- !.
value_text(jexpr(_, S), S) :- !.
value_text(ref(O, F), T) :- !, format(atom(T), '~w.~w', [O, F]).
value_text(V, V).

		 /*******************************
		 *	  translation		*
		 *******************************/

%!	drl_to_internal(+File, -Terms, -Diags) is det.
%!	drl_to_internal(+File, +Options, -Terms, -Diags) is det.
%!	drl_reading(+File, +Options, -Reading) is det.
%
%	Options: declares([declare(Type, Fields), ...]) — the field order of
%	types the file does not declare itself (a rule base written against
%	Java classes: the translator reads it from the fact model), a field
%	being `F` or `F-Kind` (`on-boolean`, `room-'object:Room'`);
%	facts([Type(V1, ...), ...]) — facts the working memory will hold (an
%	initial working memory, a driver's inserts), which the reading of the
%	fields takes into account; wording(File) or wording_text(Text) — the
%	rule base's wording table (default: `<stem>.wording` beside the file).
%
%	Reading is reading(Terms, Diags, World): World is what
%	drl_world_facts/3, drl_driver_events/4 and drl_templates/2 need.
drl_to_internal(File, Terms, Diags) :- drl_to_internal(File, [], Terms, Diags).

drl_to_internal(File, Options, Terms, Diags) :-
	drl_reading(File, Options, reading(Terms, Diags, _)).

drl_reading(File, Options, Reading) :-
	once(reading(File, Options, Reading)).

reading(File, Options, reading(Terms, Diags, World)) :-
	drl_parse(File, Rules0, Declares0, RAttrs),
	%  a rule with `enabled false` is left out of the reading (rule_terms/8
	%  says so), and shapes none of its fluents
	exclude(disabled_rule(RAttrs), Rules0, Rules),
	( memberchk(declares(Extra), Options) -> true ; Extra = [] ),
	findall(declare(T, Fs), ( member(declare(T0, Fs0), Extra), downcase_atom(T0, T),
				  \+ memberchk(declare(T, _), Declares0),
				  maplist(field_name_only, Fs0, Fs) ), Extra1),
	append(Declares0, Extra1, Declares),
	field_order(Rules, Declares, Order),
	drl_kinds(File, Extra, Kinds),
	( memberchk(facts(Facts), Options) -> true ; Facts = [] ),
	wording_lines(File, Options, WLines),
	world_of(Rules, Order, Kinds, Facts, WLines, File, World, WDiags),
	Src = src(File, 1, 0, drl),
	undeclared_diags(Order, Declares, Src, UDiags),
	logical_types(Rules, Order, Facts, Src, Logical, LDiags),
	findall(T-D, ( member(R, Rules0), rule_terms(R, RAttrs, Order, World, Logical, File, T, D) ), Pairs),
	findall(T, member(T-_, Pairs), Ts0), append(Ts0, RuleTerms),
	findall(D, member(_-D, Pairs), Ds0), append(Ds0, RuleDiags),
	%  Declarations come from the *translated* terms, not from a second parse
	%  of the right-hand sides: `modify( s ) { … }` names a variable, and
	%  re-deriving the action from it declared `modify_s` while the rules
	%  used `modify_sprinkler`.
	declarations(World, RuleTerms, File, DeclTerms),
	append(DeclTerms, RuleTerms, Terms),
	append([WDiags, UDiags, LDiags, RuleDiags], Diags).

field_name_only(F-_, F) :- !.
field_name_only(F, F).

%	The alternatives of a rule's conditions, and every pattern in them
%	(inside an accumulate too).
body_alternatives(unsupported(_), []) :- !.
body_alternatives(or(Alts), Alts) :- !.
body_alternatives(Ps, [Ps]).

body_pattern(Body, P) :-
	body_alternatives(Body, Alts), member(Ps, Alts), member(X, Ps), item_pattern(X, P).

item_pattern(P, P) :- P = pattern(_, _, _, _).
item_pattern(acc(_, _, _, Inner, _), P) :- member(P, Inner).

/* Drools facts are Java objects; LPS fluents are terms. So a type's fields
   need an *order*, and it comes from a `declare` block when there is one (or
   the fact model the caller gives) and otherwise from the fields the rules
   mention: in a constraint, as another pattern's field (`s.room`), or in
   the Java of a consequence (`politician.getName()`). A type with none of
   these is reported (undeclared_diags/4): the rules may not mention every
   field that tells its facts apart.
*/
field_order(Rules, Declares, Order) :-
	findall(Type-Fields,
		( member(declare(Type, Fields), Declares) ),
		FromDeclares),
	findall(Type-Fields,
		( member(rule(_, _, Body, _, _), Rules),
		  body_pattern(Body, pattern(_, _, Type, _)),
		  \+ memberchk(Type-_, FromDeclares),
		  findall(F, ( member(rule(_, _, B2, _, _), Rules),
			       body_pattern(B2, pattern(_, _, Type, Cs)),
			       member(C, Cs), constraint_field(C, F) ), Fs0),
		  findall(F, mentioned_field(Rules, Type, F), Fs1),
		  append(Fs0, Fs1, Fs2),
		  sort(Fs2, Fields) ),
		FromRules0),
	dedupe_keys(FromRules0, FromRules1),
	%  a type that is only inserted: its constructor's arguments, by position
	findall(Type-Fields,
		( member(rule(_, _, _, RHS, _), Rules), member(L, RHS),
		  rhs_action(L, [], A, K), memberchk(K, [insert, insert_logical]),
		  A =.. [N|Args], atom_concat(insert_, Type, N),
		  \+ memberchk(Type-_, FromDeclares), \+ memberchk(Type-_, FromRules1),
		  length(Args, Len), numlist(1, Len, Is),
		  findall(F, ( member(I, Is), format(atom(F), 'arg~w', [I]) ), Fields) ),
		FromInserts0),
	dedupe_keys(FromInserts0, FromInserts),
	append([FromDeclares, FromRules1, FromInserts], Order).

%	A field of Type named outside its pattern's constraints: `s.room` in
%	another pattern, `politician.getName()` in the consequence.
mentioned_field(Rules, Type, F) :-
	member(rule(_, _, Body, RHS, _), Rules),
	findall(V-T, ( body_pattern(Body, pattern(_, V, T, _)), V \== '' ), VTs),
	(   body_pattern(Body, pattern(_, _, _, Cs)), member(C, Cs),
	    ( C = eq(_, ref(Obj, F)) ; C = cmp(_, _, ref(Obj, F)) ),
	    memberchk(Obj-Type, VTs)
	;   member(L, RHS), member(Obj-Type, VTs), java_field(L, Obj, F)
	).

%	`obj.getRoom()`, `obj.isOn()`, `obj.room` in a line of Java.
java_field(L, Obj, F) :-
	atom_length(Obj, OL),
	sub_string(L, B, OL, _, Obj),
	(   B =:= 0 -> true
	;   B0 is B - 1, sub_string(L, B0, 1, _, Prev), string_code(1, Prev, PC),
	    \+ code_type(PC, csym), PC =\= 0'$
	),
	D is B + OL, sub_string(L, D, 1, _, "."),
	D1 is D + 1, sub_string(L, D1, _, 0, Rest),
	string_codes(Rest, RCs), ident_prefix(RCs, ICs, After), ICs \== [],
	atom_codes(Id, ICs),
	(   After = [0'(|_]
	->  ( atom_concat(get, F0, Id) ; atom_concat(is, F0, Id) ),
	    F0 \== '', sub_atom(F0, 0, 1, _, C1), char_type(C1, upper)
	;   F0 = Id
	),
	downcase_atom(F0, F).

ident_prefix([C|Cs], [C|Is], After) :- code_type(C, csym), !, ident_prefix(Cs, Is, After).
ident_prefix(Cs, [], Cs).

dedupe_keys([], []).
dedupe_keys([K-V|T], [K-V|Out]) :- exclude_key(K, T, T1), dedupe_keys(T1, Out).
exclude_key(_, [], []).
exclude_key(K, [K2-V|T], Out) :-
	( K == K2 -> Out = Out1 ; Out = [K2-V|Out1] ),
	exclude_key(K, T, Out1).

constraint_field(eq(F, _), F).
constraint_field(bind(F, _), F).
constraint_field(cmp(_, F, _), F).

%	The types that have neither a `declare` nor a fact model: their fields
%	are only those the rules mention.
undeclared_diags(Order, Declares, Src, Diags) :-
	findall(S, ( member(T-Fs, Order), \+ memberchk(declare(T, _), Declares),
		     ( Fs == [] -> S0 = 'no fields' ; atomic_list_concat(Fs, ', ', S0) ),
		     format(atom(S), '~w (~w)', [T, S0]) ), Ss),
	(   Ss == []
	->  Diags = []
	;   atomic_list_concat(Ss, '; ', List),
	    format(atom(M), 'no `declare` and no fact model for ~w: each is read with only the fields the rules mention, so facts that differ only in other fields are read as one, and a constructor''s arguments are taken in this order. Add a `declare` for each type to give its fields', [List]),
	    diag(warning, drools_undeclared_type, Src, M, D),
	    Diags = [D]
	).

/* `insertLogical`: truth maintenance. Drools withdraws a logically inserted
   fact as soon as nothing supports it, which in LPS is an intensional fluent
   — the fact holds at a time if the rule's conditions do. That reading is
   faithful when nothing else changes the type's facts: a type that a rule
   also inserts, modifies or deletes, or that the working memory holds from
   the start, needs a stored fluent, and then insertLogical is read as an
   insert, with a warning.
*/
logical_types(Rules, Order, Facts, Src, Logical, Diags) :-
	findall(T, ( member(rule(_, _, _, RHS, _), Rules), member(L, RHS),
		     rhs_action(L, Order, A, insert_logical), inserted_type(A, T) ), Ts0),
	sort(Ts0, Cands),
	findall(T-Why, ( member(T, Cands), logical_conflict(Rules, Order, Facts, T, Why) ), Conflicts0),
	dedupe_keys(Conflicts0, Conflicts),
	findall(T, ( member(T, Cands), \+ memberchk(T-_, Conflicts) ), Logical),
	findall(D, ( member(T-Why, Conflicts),
		     format(atom(M), 'insertLogical of ~w is read as an ordinary insert, because ~w: the fact is not withdrawn when the conditions that inserted it stop holding, as Drools would withdraw it', [T, Why]),
		     diag(warning, drools_insert_logical, Src, M, D) ), Diags).

inserted_type(A, T) :- A =.. [N|_], atom_concat(insert_, T, N).

logical_conflict(Rules, Order, _, T, 'a rule also inserts it') :-
	member(rule(_, _, _, RHS, _), Rules), member(L, RHS),
	rhs_action(L, Order, A, insert), inserted_type(A, T).
logical_conflict(Rules, Order, _, T, 'a rule modifies or deletes it') :-
	member(rule(_, _, Body, RHS, _), Rules), member(L, RHS),
	(   rhs_action(L, Order, A, K), memberchk(K, [modify, retract]),
	    A =.. [N|_], ( atom_concat(modify_, T, N) ; atom_concat(retract_, T, N) )
	;   ( sub_string(L, B, _, _, "modify(") -> Off = 7
	    ; sub_string(L, B, _, _, "retract(") -> Off = 8
	    ; sub_string(L, B, _, _, "delete(") -> Off = 7 ),
	    P is B + Off, sub_string(L, P, _, 0, Rest), sub_string(Rest, E, 1, _, ")"),
	    sub_string(Rest, 0, E, _, VS), normalize_space(atom(V), VS),
	    body_pattern(Body, pattern(_, V, T, _))
	).
logical_conflict(_, _, Facts, T, 'the working memory holds such facts from the start') :-
	member(F, Facts), ( atom(F) ; compound(F) ), functor(F, T, _).

declarations(World, RuleTerms, File, Terms) :-
	world_fluents(World, Fluents),
	%  By name/arity, not by term: `sort/2` on the templates themselves keeps
	%  every copy, because two fresh `insert_discount(_,_)` are different
	%  terms under the standard order. The declaration then listed the same
	%  action four times.
	findall(N2/A2, ( member(t(Term, _), RuleTerms), term_action(Term, A),
			 functor(A, N2, A2) ), Sigs0),
	sort(Sigs0, Sigs),
	findall(Tmpl, ( member(N3/A3, Sigs), functor(Tmpl, N3, A3) ), Actions),
	Src = src(File, 1, 0, drl),
	findall(t(fluents(Fluents), Src), Fluents \== [], F1),
	findall(t(actions(Actions), Src), Actions \== [], A1),
	append(F1, A1, Terms).

term_action(reactive_rule(_, Cons), A) :- member(happens(A, _, _), Cons).
term_action(reactive_rule(_, Cons, _), A) :- member(happens(A, _, _), Cons).
term_action(initiated(happens(A, _, _), _, _), A).
term_action(terminated(happens(A, _, _), _, _), A).
term_action(updated(happens(A, _, _), _, _, _), A).

/* One rule → one reactive rule (one per alternative, when its conditions
   have `or`), plus the causal laws its right-hand side implies, in the world
   reading (below): the patterns are states of the world, and each change
   the consequence makes to working memory is an event with its
   `initiates`/`terminates`/`updates`. An `insertLogical` is an intensional
   fluent instead (logical_types/6), and the Java of the consequence the
   external action java_leaf(RuleName).

   All the patterns of a Drools rule match ONE state of working memory, so
   they share one time T; the consequence's actions start at T, together —
   a DRL consequence is one block — and so does the Logical English, which
   then needs no times at all (le_lps_surface.md §3.1).
*/
rule_terms(rule(Name, Salience, Body, RHS, Line), RAttrs, Order, World, Logical, File, Terms, Diags) :-
	Src = src(File, Line, 0, drl),
	( memberchk(attrs(Line, _, Attrs), RAttrs) -> true ; Attrs = [] ),
	(   disabled(Attrs)
	->  Terms = [],
	    format(atom(M), 'rule "~w" has `enabled false`: Drools never fires it, so the program leaves it out', [Name]),
	    diag(info, drools_disabled, Src, M, D),
	    Diags = [D]
	;   rule_terms_(Name, Salience, Body, RHS, Attrs, Order, World, Logical, Src, Terms, Diags0),
	    attribute_diags(Name, Attrs, Src, ADiags),
	    append(ADiags, Diags0, Diags)
	).

rule_terms_(Name, Salience, Body, RHS, Attrs, Order, World, Logical, Src, Terms, Diags) :-
	(   Body = unsupported(Why)
	->  Terms = [],
	    format(atom(M), 'rule "~w" is not translated: ~w. The program has nothing in its place', [Name, Why]),
	    diag(warning, drools_untranslated, Src, M, D),
	    Diags = [D]
	;   body_alternatives(Body, Alts),
	    findall(Ts-Ds, ( member(Ps, Alts),
			     alt_terms(Name, Salience, Attrs, Ps, RHS, Order, World, Logical, Src, Ts, Ds) ), Pairs),
	    findall(T, ( member(Ts-_, Pairs), member(T, Ts) ), Terms0),
	    dedupe_variants(Terms0, Terms),
	    ( Pairs = [_-Diags0|_] -> true ; Diags0 = [] ),
	    length(Alts, NA),
	    (   NA > 1
	    ->  format(atom(M), 'rule "~w" has `or` between its conditions: it is read as ~w rules, one for each alternative, as Drools makes one subrule for each', [Name, NA]),
		diag(info, drools_or, Src, M, D),
		Diags = [D|Diags0]
	    ;   Diags = Diags0
	    )
	).

%	(a causal law two alternatives share is written once)
dedupe_variants([], []).
dedupe_variants([T|Ts], [T|Out]) :-
	exclude(=@=(T), Ts, Ts1),
	dedupe_variants(Ts1, Out).

alt_terms(Name, Salience, Attrs, Patterns, RHS, Order, World, Logical, Src, Terms, Diags) :-
	%  One variable map per rule: `Fire(room : room)` binds `room`, and the
	%  `room == room` of the next pattern refers to *that* variable. Without
	%  the map each pattern gets its own, and the rule says "a fire and a
	%  sprinkler, anywhere" — which is not what it says.
	rule_var_map(Patterns, Map),
	b_setval(drl_rule_patterns, []),
	maplist(pattern_literal(Order, Map, T), Patterns, Conds0),
	%  `room == s.room` (a field of another pattern's fact) and `age > 25`
	%  (a comparison): after every pattern has its fluent
	resolve_references(Patterns, Conds0, Order, Map, Conds0b, Extra),
	append(Conds0b, Extra, Conds1),
	rhs_actions(RHS, Order, Map, Patterns, Actions00, Java, Goals),
	%  No findall/3 anywhere near these: it copies, and a copied action no
	%  longer shares the rule's variables with the antecedent that bound
	%  them. `insert(new Sprinkler(room, on))` would insert a sprinkler in
	%  *some* room rather than in the burning one.
	%  (the values the consequence computes, `V is C + 1`, after the
	%  conditions that bind what they are computed from)
	append(Conds1, Goals, Conds1g),
	world_conditions(World, Conds1g, Conds2),
	logical_inserts(Actions00, Logical, World, Order, T, Conds2, Name, Src, Actions0, IntTerms, LDiags),
	world_changes(World, Order, Actions0, Events, Laws),
	refraction_guard(World, Order, Actions0, T, Conds2, Conds3),
	loop_attribute(Attrs, Loop),
	no_loop_guard(Loop, World, Actions0, Goals, T, Conds3, Conds, Name, Src, NDiags),
	happens_from(Events, T, ECons),
	(   Java = [_|_] -> JCons = [happens(java_leaf(Name), T, _)] ; JCons = [] ),
	append(ECons, JCons, Cons),
	(   Cons == [] -> RuleTerms = []
	;   Salience =:= 0 -> RuleTerms = [t(reactive_rule(Conds, Cons), Src)]
	;   RuleTerms = [t(reactive_rule(Conds, Cons, Salience), Src)]
	),
	laws_at(Laws, Src, Effects),
	append([RuleTerms, IntTerms, Effects], Terms),
	keys_of(Actions00, Actions),
	rule_diags(Name, Salience, Java, Actions, Src, Diags0),
	append([Diags0, LDiags, NDiags], Diags).

/* Rule attributes (rule_attributes/2) — what each means in Drools, checked
   against Drools 10 (a KieSession fed the same facts), and what the reading
   makes of it:

     enabled false        the rule never fires: left out (info)
     no-loop              the rule's own change does not activate it again:
                          the condition that its change is not made already
                          (no_loop_guard/10); not translated, with a
                          warning, when the change computes a field's new
                          value from its old one (`count + 1`)
     lock-on-active       no activation at all while its agenda group has
                          the focus, whoever's change made it: read as
                          no-loop, with a warning (matches that other rules
                          create during a run are not held back)
     agenda-group G       fires only while G has the focus, which Java (or
                          `auto-focus`) gives it — read as if G always had
                          it, with a warning ("MAIN", the default: nothing)
     auto-focus           G takes the focus when the rule is activated: the
                          rule fires, in an order of its own (a warning)
     activation-group G   one activation of the whole group fires and
                          cancels the others, whatever rule and match they
                          are: not translated (a warning)
     ruleflow-group G     fires only while a process activates G: read as if
                          it did (a warning)
     date-effective,      a calendar window: read as always in effect (a
     date-expires,        warning)
     calendars
     duration, timer      fires later, on a clock: read as firing at once (a
                          warning)
     dialect              the language of the consequence: nothing to
                          translate (info)
     salience (expr)      a priority computed when the rule fires: not
                          translated (a warning)
     extends R            inherits R's conditions: the rule is not
                          translated (rule_of/6)
*/
disabled(Attrs) :- memberchk(a(enabled, (false)), Attrs).

disabled_rule(RAttrs, rule(_, _, _, _, L)) :- memberchk(attrs(L, _, As), RAttrs), disabled(As).

attr_on(Attrs, A) :- memberchk(a(A, V), Attrs), memberchk(V, [true, none]).

%	The loop attribute a rule's guard answers to: none, no_loop or
%	lock_on_active.
loop_attribute(Attrs, Loop) :-
	(   attr_on(Attrs, 'lock-on-active') -> Loop = lock_on_active
	;   attr_on(Attrs, 'no-loop') -> Loop = no_loop
	;   Loop = none
	).

attribute_diags(Name, Attrs, Src, Diags) :-
	findall(D, ( member(a(A, V), Attrs), attribute_diag(A, V, Attrs, Name, Sev, M),
		     diag(Sev, drools_attribute, Src, M, D) ), Diags).

attribute_diag(salience, V, _, Name, warning, M) :-
	\+ number(V), attr_value_text(V, VT),
	format(atom(M), 'rule "~w": salience ~w is not a number (a priority computed when the rule fires), which is not translated: the rule is read with no priority', [Name, VT]).
attribute_diag(enabled, V, _, Name, warning, M) :-
	\+ memberchk(V, [true, (false), none]), attr_value_text(V, VT),
	format(atom(M), 'rule "~w": enabled ~w is computed when the rules are loaded, which is not translated: the rule is read as enabled', [Name, VT]).
attribute_diag('agenda-group', V, Attrs, Name, warning, M) :-
	attr_value_text(V, VT), V \== str("MAIN"), V \== none,
	(   attr_on(Attrs, 'auto-focus')
	->  format(atom(M), 'rule "~w": agenda-group ~w with auto-focus: the group takes the focus when the rule is activated, so it fires, but Drools fires the groups one at a time, in the order of its focus stack, and LPS fires every rule whose conditions hold: the firing order may differ', [Name, VT])
	;   format(atom(M), 'rule "~w": agenda-group ~w is ignored: Drools fires the rule only while its group has the focus, which Java gives it (`getAgenda().getAgendaGroup(...).setFocus()`), and the rule base alone never does; the program reads the rule as if the group always had the focus', [Name, VT])
	).
attribute_diag('activation-group', V, _, Name, warning, M) :-
	attr_value_text(V, VT),
	format(atom(M), 'rule "~w": activation-group ~w is ignored: in Drools the first activation of the group to fire cancels every other one (of any rule of the group, on any facts), which LPS, firing every rule on every match that holds, cannot say; the rule fires on each of its matches', [Name, VT]).
attribute_diag('ruleflow-group', V, _, Name, warning, M) :-
	attr_value_text(V, VT),
	format(atom(M), 'rule "~w": ruleflow-group ~w is ignored: Drools fires the rule only while a process (jBPM) activates its group, and the rule base alone never does; the program reads the rule as if the group were active', [Name, VT]).
attribute_diag(A, V, _, Name, warning, M) :-
	memberchk(A, ['date-effective', 'date-expires', calendars]),
	attr_value_text(V, VT),
	format(atom(M), 'rule "~w": ~w ~w is ignored: Drools fires the rule only in that window of the calendar, and the program has no calendar; the rule is read as always in effect', [Name, A, VT]).
attribute_diag(A, V, _, Name, warning, M) :-
	memberchk(A, [duration, timer]),
	attr_value_text(V, VT),
	format(atom(M), 'rule "~w": ~w ~w is ignored: Drools fires the rule later, on its clock, and LPS has no such clock; the rule is read as firing as soon as its conditions hold', [Name, A, VT]).
attribute_diag(dialect, V, _, Name, info, M) :-
	attr_value_text(V, VT),
	format(atom(M), 'rule "~w": dialect ~w says in what language its consequence is written, which changes nothing in the reading', [Name, VT]).
attribute_diag('lock-on-active', V, _, Name, warning, M) :-
	memberchk(V, [true, none]),
	format(atom(M), 'rule "~w": lock-on-active is read as no-loop: Drools also holds back the rule''s activations that other rules'' changes create while its agenda group has the focus (during one run of the rules), which LPS, with no runs, cannot say; the rule fires on such matches', [Name]).
attribute_diag(A, V, _, Name, warning, M) :-
	\+ known_attribute(A), A \== '?',
	attr_value_text(V, VT0), ( VT0 == none -> VT = '' ; format(atom(VT), ' ~w', [VT0]) ),
	format(atom(M), 'rule "~w": the attribute `~w~w` is not one the reader knows, and is ignored', [Name, A, VT]).
attribute_diag('?', str(W), _, Name, warning, M) :-
	format(atom(M), 'rule "~w": `~w` before `when` is not an attribute the reader knows, and is ignored', [Name, W]).

/* no-loop: Drools does not activate the rule again because of a change its
   own consequence made. Read as a condition: the rule does not fire when
   the change it would make is made already — the fact it would insert holds,
   the fields its modify sets have those values — which is when its own
   change would have activated it again. It fires once a change from
   elsewhere undoes its own. (What Drools does and this does not: fire, a
   first time, a modify that changes nothing.) A delete guards itself.

   A modify that computes a field's new value from its old one (`count =
   count + 1`) is never made already: then no condition says it, and the
   attribute is not translated (a warning).
*/
no_loop_guard(none, _, _, _, _, Conds, Conds, _, _, []) :- !.
no_loop_guard(Loop, W, Actions0, Goals, T, Conds0, Conds, Name, Src, Diags) :-
	(   Actions0 == []
	->  Conds = Conds0, Diags = []
	;   made_already(Actions0, W, Goals, T, Lits, Computed),
	    (   Computed = [F|_]
	    ->  Conds = Conds0,
		format(atom(M), 'rule "~w": ~w is not translated: its consequence computes the new ~w from the old one, so whether its change is made already cannot be told from the state, and LPS fires the rule in every cycle its conditions hold (Drools fires it once)', [Name, Loop, F]),
		loop_word(Loop, LW), atomic_list_concat(Parts, Loop, M), atomic_list_concat(Parts, LW, M1),
		diag(warning, drools_attribute, Src, M1, D), Diags = [D]
	    ;   negated_lits(Lits, T, Guard),
		(   Guard == none
		->  Conds = Conds0
		;   Guard = holds(not(G), _), \+ is_list(G),
		    member(holds(not(G0), _), Conds0), \+ is_list(G0), G0 == G
		->  Conds = Conds0
		;   append(Conds0, [Guard], Conds)
		),
		(   Loop == no_loop
		->  format(atom(M), 'rule "~w" has no-loop (Drools does not activate it again by its own change): it does not fire when its change is made already', [Name]),
		    diag(info, drools_no_loop, Src, M, D), Diags = [D]
		;   Diags = []
		)
	    )
	).

loop_word(no_loop, 'no-loop').
loop_word(lock_on_active, 'lock-on-active').

%	What holds once the changes are made: holds(F, T) (a fact inserted, a
%	state turned on), holds(not(F), T) (turned off), Old == New (a field
%	set). Computed: the fields whose new value is computed from the old.
made_already([], _, _, _, [], []).
made_already([A-What|As], W, Goals, T, Lits, Computed) :-
	(   What = modify(Old, New), raw_shape(W, Old, S, OArgs)
	->  New =.. [_|NArgs], S = shape(_, Fields, Kept, Bools, _),
	    kept_args(S, OArgs, K),
	    modify_lits(Fields, OArgs, NArgs, S-K, Kept, Bools, W, Goals, T, L1, C1)
	;   string(What), A =.. [N|_], atom_concat(insert_, _, N)
	->  insert_lits(A, W, T, L1), C1 = []
	;   L1 = [], C1 = []
	),
	made_already(As, W, Goals, T, L2, C2),
	append(L1, L2, Lits), append(C1, C2, Computed).

insert_lits(A, W, T, Lits) :-
	A =.. [N|Args], atom_concat(insert_, Ty, N),
	shape_of(W, Ty, shape(Ty, Fields, _, _, _)),
	length(Fields, Len), functor(F, Ty, Len), F =.. [_|FArgs], prefix_unify(Args, FArgs),
	(   raw_shape(W, F, S, RArgs)
	->  kept_args(S, RArgs, K), exists_fluent(W, S, K, E),
	    S = shape(_, _, _, Bools, _),
	    findall(B, ( member(B, Bools), field_arg(S, RArgs, B, V), V == true ), Ons),
	    state_heads(Ons, W, S, K, SHs),
	    holds_all_at([E|SHs], T, Lits)
	;   Lits = []
	).

holds_all_at([], _, []).
holds_all_at([F|Fs], T, [holds(F, T)|Ls]) :- holds_all_at(Fs, T, Ls).

modify_lits([], _, _, _, _, _, _, _, _, [], []).
modify_lits([F|Fs], [O|Os], [N|Ns], S-K, Kept, Bools, W, Goals, T, Lits, Computed) :-
	(   O == N
	->  L = [], C = []
	;   memberchk(F, Bools), N == true
	->  state_fluent(W, S, F, K, SF), L = [holds(SF, T)], C = []
	;   memberchk(F, Bools), N == (false)
	->  state_fluent(W, S, F, K, SF), L = [holds(not(SF), T)], C = []
	;   memberchk(F, Kept), computed_from(N, O, Goals)
	->  L = [], C = [F]
	;   memberchk(F, Kept)
	->  L = [O == N], C = []
	;   L = [], C = []
	),
	modify_lits(Fs, Os, Ns, S-K, Kept, Bools, W, Goals, T, Lits0, Computed0),
	append(L, Lits0, Lits), append(C, Computed0, Computed).

%	N is computed (by one of the rule's `is` goals) from O.
computed_from(N, O, Goals) :-
	var(N), var(O),
	member(G, Goals), G = (X is E), X == N, !,
	term_variables(E, Vs),
	(   member(V, Vs), V == O -> true
	;   member(V, Vs), computed_from(V, O, Goals)
	).

%	The condition that not all of Lits hold.
negated_lits([], _, none) :- !.
negated_lits([holds(not(F), T)], _, holds(F, T)) :- !.
negated_lits([holds(F, T)], _, holds(not(F), T)) :- !.
negated_lits([O == N], _, O \= N) :- !.
negated_lits(Lits, _, Os \= Ns) :-
	forall(member(L, Lits), L = (_ == _)), !,
	findall(O, member(O == _, Lits), Os0), findall(N, member(_ == N, Lits), Ns0),
	Os =.. [f|Os0], Ns =.. [f|Ns0].
negated_lits(Lits, T, holds(not(Lits), T)).

happens_from([], _, []).
happens_from([E|Es], T, [happens(E, T, _)|Out]) :- happens_from(Es, T, Out).

laws_at([], _, []).
laws_at([L|Ls], Src, [t(L, Src)|Out]) :- laws_at(Ls, Src, Out).


/* The insertLogical actions of a consequence whose type is read as an
   intensional fluent: `l_int(holds(Fact, T), Conditions)`, with the rule's
   conditions (not its refraction guard) — and, for a boolean field it sets
   to true, the state too. The rest stay actions. A fact whose values the
   conditions do not bind cannot be an intensional fluent, and is inserted.
*/
logical_inserts([], _, _, _, _, _, _, _, [], [], []).
logical_inserts([A-L|As], Logical, W, Order, T, Conds, Name, Src, Rest, Ints, Diags) :-
	(   string(L), rhs_action(L, Order, _, insert_logical),
	    inserted_type(A, Type), memberchk(Type, Logical),
	    inserted_fact(A, Order, F), raw_shape(W, F, S, Args)
	->  kept_args(S, Args, K), exists_fluent(W, S, K, E),
	    S = shape(_, _, _, Bools, _),
	    findall(B, ( member(B, Bools), field_arg(S, Args, B, V), V == true ), Ons),
	    state_heads(Ons, W, S, K, SHs),
	    Heads = [E|SHs],
	    term_variables(Heads, HVs), term_variables(Conds, CVs),
	    (   forall(member(HV, HVs), ( member(CV, CVs), CV == HV ))
	    ->  int_terms(Heads, T, Conds, Src, Ints1),
		format(atom(M), 'rule "~w": insertLogical of ~w, so the fact holds for as long as the rule''s conditions do (Drools'' truth maintenance): an intensional fluent, not an event', [Name, Type]),
		diag(info, drools_insert_logical, Src, M, D),
		Rest = Rest1, Diags = [D|Diags1]
	    ;   format(atom(M), 'rule "~w": insertLogical of ~w is read as an ordinary insert, because the conditions do not give all its values: the fact is not withdrawn when they stop holding, as Drools would withdraw it', [Name, Type]),
		diag(warning, drools_insert_logical, Src, M, D),
		Ints1 = [], Rest = [A-L|Rest1], Diags = [D|Diags1]
	    ),
	    append(Ints1, Ints2, Ints)
	;   Rest = [A-L|Rest1], Ints = Ints2, Diags = Diags1
	),
	logical_inserts(As, Logical, W, Order, T, Conds, Name, Src, Rest1, Ints2, Diags1).

state_heads([], _, _, _, []).
state_heads([B|Bs], W, S, K, [F|Fs]) :- state_fluent(W, S, B, K, F), state_heads(Bs, W, S, K, Fs).

int_terms([], _, _, _, []).
int_terms([H|Hs], T, Conds, Src, [t(l_int(holds(H, T), Conds), Src)|Out]) :-
	int_terms(Hs, T, Conds, Src, Out).

rule_var_map(Patterns, Map) :-
	findall(V, ( member(X, Patterns), item_pattern(X, pattern(_, _, _, Cs)), member(bind(_, V), Cs) ), Vs0),
	findall(V, ( member(X, Patterns), item_pattern(X, pattern(_, V, _, _)), V \== '' ), Vs1),
	findall(V, member(acc(V, _, _, _, _), Patterns), Vs2),
	append([Vs0, Vs1, Vs2], Vs3), sort(Vs3, Vars),
	findall(V-_, member(V, Vars), Map).

pattern_literal(Order, Map, T, acc(RV, Fn, AV, Inner, RCmps), acc_lit(Fn, ASlot, InnerConds, RSlot, Goals, T)) :- !,
	maplist(pattern_literal(Order, Map, T), Inner, IC0),
	resolve_references(Inner, IC0, Order, Map, IC1, IE),
	append(IC1, IE, InnerConds),
	( memberchk(RV-RSlot, Map) -> true ; true ),
	( AV \== '', memberchk(AV-ASlot, Map) -> true ; true ),
	maplist(acc_cmp(Order, Map, RSlot), RCmps, Goals).
pattern_literal(Order, Map, T, pattern(Kind, Var, Type, Constraints), Literal) :-
	fluent_term(Type, Constraints, Order, Map, F),
	(   Var \== '', nb_current(drl_rule_patterns, PFs0) -> b_setval(drl_rule_patterns, [Var-Type-F|PFs0])
	;   true
	),
	( Kind == neg -> Literal = holds(not(F), T) ; Literal = holds(F, T) ).

acc_cmp(Order, Map, R, Op-V0, G) :- value_slot(V0, Order, Map, V), cmp_goal(Op, R, V, G).

/* Fill the argument slots from the constraints.
 *
 * Not with forall/2, which was the first attempt: forall is \+ (C, \+ A), so
 * every binding it makes is undone on the way out and the fluent comes back
 * with all-fresh arguments — a rule that reads `Fire(room: r), Sprinkler(room
 * == r)` then means "a fire and a sprinkler, anywhere".
 */
fluent_term(Type, Constraints, Order, Map, F) :-
	( memberchk(Type-Fields, Order) -> true ; Fields = [] ),
	length(Fields, N),
	functor(F, Type, N),
	fill_fields(Fields, 1, Constraints, Map, F).

fill_fields([], _, _, _, _).
fill_fields([Field|Fs], I, Constraints, Map, F) :-
	(   member(C, Constraints), constraint_field(C, Field)
	->  arg(I, F, Slot), constraint_value(C, Map, Slot)
	;   true
	),
	I1 is I + 1,
	fill_fields(Fs, I1, Constraints, Map, F).

%	`room == room` is a *variable reference* when something bound `room`
%	earlier in the rule, and a constant otherwise. Drools tells them apart
%	by scope; so do we.
constraint_value(eq(_, ref(_, _)), _, _) :- !.           % resolve_references/6
constraint_value(cmp(_, _, _), _, _) :- !.
constraint_value(eq(_, V), Map, Slot) :-
	( memberchk(V-Var, Map) -> Slot = Var ; Slot = V ).
constraint_value(bind(_, V), Map, Slot) :-
	( memberchk(V-Var, Map) -> Slot = Var ; true ).

%	A reference to a field of another pattern's fact unifies the two slots;
%	a comparison becomes a condition on the slot — after the patterns for a
%	positive pattern, and inside the negation for a `not` one (`not Person(
%	age > 65 )` is no person over 65, not no person at all). The fluents
%	are the patterns' own (Conds), so no copy is made anywhere.
resolve_references([], [], _, _, [], []).
resolve_references([P|Ps], [Lit|Ls], Order, Map, [Lit1|Ls1], Extra) :-
	(   P = pattern(Kind, _, Type, Cs)
	->  Lit = holds(F0, T), ( F0 = not(F) -> true ; F = F0 ),
	    ( memberchk(Type-Fields, Order) -> true ; Fields = [] ),
	    refs_of(Cs, Fields, F, Order, Map, Cmps),
	    (   Kind == neg, Cmps \== []
	    ->  Lit1 = holds(not([holds(F, T)|Cmps]), T), E1 = []
	    ;   Lit1 = Lit, E1 = Cmps
	    )
	;   Lit1 = Lit, E1 = []          % an accumulate resolves its own
	),
	resolve_references(Ps, Ls, Order, Map, Ls1, E2),
	append(E1, E2, Extra).

refs_of([], _, _, _, _, []).
refs_of([C|Cs], Fields, F, Order, Map, Extra) :-
	(   C = eq(Field, ref(Obj, Fld)), nth1(I, Fields, Field)
	->  ( ref_slot(Obj, Fld, Order, Map, Slot) -> arg(I, F, Slot) ; true ), Extra = Extra1
	;   C = cmp(Op, Field, V0), nth1(I, Fields, Field)
	->  arg(I, F, Slot),
	    value_slot(V0, Order, Map, V),
	    cmp_goal(Op, Slot, V, G),
	    Extra = [G|Extra1]
	;   Extra = Extra1
	),
	refs_of(Cs, Fields, F, Order, Map, Extra1).

%	The patterns of the rule being built, by their variable (set by
%	alt_terms/10 through b_setval, so no copy is made).
ref_slot(Obj, Fld, Order, _Map, Slot) :-
	b_getval(drl_rule_patterns, PFs),
	member(Obj-Type-F, PFs), !,
	memberchk(Type-Fields, Order), nth1(I, Fields, Fld), arg(I, F, Slot).

value_slot(ref(O, Fd), Order, Map, V) :- !, ( ref_slot(O, Fd, Order, Map, V) -> true ; V = O ).
value_slot(V0, _, Map, V) :- ( memberchk(V0-X, Map) -> V = X ; V = V0 ).

cmp_goal('!=', X, Y, X \= Y).
cmp_goal('>', X, Y, X > Y).
cmp_goal('<', X, Y, X < Y).
cmp_goal('>=', X, Y, X >= Y).
cmp_goal('<=', X, Y, X =< Y).
cmp_goal('==', X, Y, X =:= Y).

/* Right-hand sides. Four shapes are understood; everything else is a leaf. */
rhs_action(Line, Order, Action, Kind) :-
	(   sub_string(Line, B, _, _, "insert("), \+ sub_string(Line, _, _, _, "insertLogical")
	->  Kind = insert, args_after(Line, B, 7, Type, Args), action_name(insert, Type, Args, Order, Action)
	;   sub_string(Line, B, _, _, "insertLogical(")
	->  Kind = insert_logical, args_after(Line, B, 14, Type, Args),
	    action_name(insert, Type, Args, Order, Action)
	;   ( sub_string(Line, B, _, _, "retract(") -> Off = 8 ; sub_string(Line, B, _, _, "delete(") -> Off = 7 )
	->  Kind = retract, args_after(Line, B, Off, Type, Args), action_name(retract, Type, Args, Order, Action)
	;   sub_string(Line, B, _, _, "modify(")
	->  Kind = modify, args_after(Line, B, 7, Type, Args), action_name(modify, Type, Args, Order, Action)
	;   fail
	).

args_after(Line, B, Off, Type, Args) :-
	P is B + Off,
	sub_string(Line, P, _, 0, Rest),
	string_codes(Rest, RCs), close_paren(RCs, ICs, _), string_codes(Inner, ICs),
	normalize_space(string(I2), Inner),
	( sub_string(I2, 0, 4, _, "new ") -> sub_string(I2, 4, _, 0, I3) ; I3 = I2 ),
	(   sub_string(I3, P2, 1, _, "(")
	->  sub_string(I3, 0, P2, _, T0), P3 is P2 + 1,
	    sub_string(I3, P3, _, 0, A0), string_codes(A0, ACs),
	    close_paren(ACs, InCs, _), string_codes(AText, InCs),
	    top_split(AText, [","], Parts),
	    findall(A, ( member(S, Parts), S \== "", java_value(S, A) ), Args)
	;   T0 = I3, Args = []
	),
	normalize_space(string(T1), T0),
	string_lower(T1, TL), atom_string(Type, TL).

action_name(Op, Type, Args, _Order, Action) :-
	atomic_list_concat([Op, '_', Type], Name),
	Action =.. [Name|Args].

/* An action's arguments name the rule's variables where they match one — and
   the mapping has to be an explicit recursion, not findall/3, for the same
   reason fluent_term/5 is: findall copies its solutions, so the variable the
   action shares with the antecedent would be a copy of it and share nothing.
*/
keys_of([], []).
keys_of([K-_|T], [K|Out]) :- keys_of(T, Out).

%	rhs_actions(+RHS, +Order, +Map, +Patterns, -Actions, -Java, -Goals):
%	the changes (A-What), the statements that are Java (j(Line, Why), Why
%	none or value(Text): a change with a value the reader cannot compute),
%	and the goals that compute the changes' values (`V is C + 1`).
rhs_actions([], _, _, _, [], [], []).
rhs_actions([L|Ls], Order, Map, Patterns, Out, Java, Goals) :-
	(   ( L == "" ; sub_string(L, 0, _, _, "//") )
	->  Out = Rest, Java = Java1, Goals = Goals1
	;   modify_action(L, Order, Map, Patterns, A, Old, New, Goals, Goals1)
	->  Out = [A-modify(Old, New)|Rest], Java = Java1
	;   retract_action(L, Order, Map, Patterns, A, Gone)
	->  Out = [A-retract(Gone)|Rest], Java = Java1, Goals = Goals1
	;   rhs_action(L, Order, A0, K), K \== modify,
	    bind_action(A0, Order, Map, A, Goals, Goals1)
	->  Out = [A-L|Rest], Java = Java1
	;   Out = Rest, Goals = Goals1,
	    (   change_value_text(L, Order, Map, Patterns, VT) -> Why = value(VT) ; Why = none ),
	    Java = [j(L, Why)|Java1]
	),
	rhs_actions(Ls, Order, Map, Patterns, Rest, Java1, Goals1).

%	The value that keeps a change from being read: the first argument of an
%	insert, or value of a modify, that resolve_value/6 cannot compute.
change_value_text(L, Order, Map, Patterns, Text) :-
	(   rhs_action(L, Order, A0, K), memberchk(K, [insert, insert_logical, retract])
	->  A0 =.. [_|Vs]
	;   sub_string(L, B, _, _, "modify("), P is B + 7, sub_string(L, P, _, 0, Rest),
	    assignments(Rest, Assigns), pairs_values(Assigns, Vs)
	),
	member(V, Vs), \+ resolve_value(V, Order, Map, _, _, _), !,
	value_text(V, Text),
	ignore(Patterns = []).

/* `retract( o )` — and `o` is a *pattern variable*, not a type.
 *
 * The generic path lowercases whatever is inside the parentheses and treats it
 * as a type name, which for `retract(o)` produced an action called `retract_o`
 * that terminated nothing at all: the rule fired forever and the fact stayed.
 * Drools binds `o` in the `when` side, so the pattern is right there — resolve
 * it the same way `modify` does, and terminate the fluent the variable stands
 * for.
 */
retract_action(Line, Order, Map, Patterns, Action, Gone) :-
	( sub_string(Line, B, _, _, "retract(") -> Off = 8
	; sub_string(Line, B, _, _, "delete(") -> Off = 7 ),
	P is B + Off,
	sub_string(Line, P, _, 0, Rest),
	sub_string(Rest, E, 1, _, ")"),
	sub_string(Rest, 0, E, _, VarS),
	normalize_space(atom(Var), VarS),
	member(pattern(_, Var, Type, Constraints), Patterns),
	!,
	pattern_fluent(Var, Type, Constraints, Order, Map, Gone),
	Gone =.. [_|Args],
	atomic_list_concat([retract, '_', Type], Name),
	Action =.. [Name|Args].

/* `modify( s ) { on = true }` — Drools' update-in-place, and the reason it
   matters is that an `insert` of a changed copy leaves the old fact in working
   memory. The variable names a pattern, the pattern names a type, and the
   braces say which field changes; the result is an LPS action that terminates
   the old fluent and initiates the new one, which is exactly `updates`.
*/
modify_action(Line, Order, Map, Patterns, Action, Old, New, Goals0, Goals) :-
	sub_string(Line, B, _, _, "modify("),
	P is B + 7,
	sub_string(Line, P, _, 0, Rest),
	sub_string(Rest, E, 1, _, ")"),
	sub_string(Rest, 0, E, _, VarS),
	normalize_space(atom(Var), VarS),
	member(pattern(_, Var, Type, Constraints), Patterns),
	!,
	pattern_fluent(Var, Type, Constraints, Order, Map, Old),
	( memberchk(Type-Fields, Order) -> true ; Fields = [] ),
	assignments(Rest, Assigns0),
	resolve_assigns(Assigns0, Order, Map, Assigns, Goals0, Goals),
	copy_with(Old, Fields, Assigns, New),
	New =.. [_|NewArgs],
	atomic_list_concat([modify, '_', Type], Name),
	Action =.. [Name|NewArgs].

%	The fluent the rule's pattern for Var matched (the same term, so the
%	action shares its variables), else one made from the constraints.
pattern_fluent(Var, Type, Constraints, Order, Map, F) :-
	(   nb_current(drl_rule_patterns, PFs), member(V-Type-F0, PFs), V == Var
	->  F = F0
	;   fluent_term(Type, Constraints, Order, Map, F)
	).

resolve_assigns([], _, _, [], Gs, Gs).
resolve_assigns([F-V|As], Order, Map, [F-R|Rs], Gs0, Gs) :-
	resolve_value(V, Order, Map, R, Gs0, Gs1),
	resolve_assigns(As, Order, Map, Rs, Gs1, Gs).

%	`{ f = v, g = w }` → [f-v, g-w]; `{ setOn( true ) }` (real DRL's setters)
%	→ [on-true]; a value as java_value/2 reads it.
assignments(S, Assigns) :-
	(   sub_string(S, B, 1, _, "{"), sub_string(S, A, 1, _, "}"), A > B
	->  Start is B + 1, Len is A - Start,
	    sub_string(S, Start, Len, _, Inner),
	    top_split(Inner, [",", ";"], Parts),
	    findall(F-V, ( member(Part, Parts), Part \== "", once(assignment(Part, F, V)) ), Assigns)
	;   Assigns = []
	).

assignment(Part, F, V) :-
	(   sub_string(Part, B0, 1, _, "="), sub_string(Part, 0, B0, _, FS0),
	    normalize_space(string(FS), FS0), FS \== "", atom_string(FA, FS), identifier(FA),
	    B1 is B0 + 1, \+ sub_string(Part, B1, 1, _, "=")
	->  sub_string(Part, B1, _, 0, VS),
	    string_lower(FS, FL), atom_string(F, FL), java_value(VS, V)
	;   normalize_space(string(P), Part),
	    sub_string(P, 0, 3, _, "set"), sub_string(P, B, 1, _, "("), sub_string(P, _, 1, 0, ")"),
	    Len is B - 3, sub_string(P, 3, Len, _, FS),
	    string_lower(FS, FL), atom_string(F, FL),
	    B1 is B + 1, sub_string(P, B1, _, 1, VS), java_value(VS, V)
	).

copy_with(Old, Fields, Assigns, New) :-
	Old =.. [Name|Args],
	replace_fields(Fields, 1, Args, Assigns, NewArgs),
	New =.. [Name|NewArgs].

replace_fields([], _, Args, _, Args).
replace_fields([F|Fs], I, Args, Assigns, Out) :-
	(   memberchk(F-V, Assigns)
	->  replace_nth(I, Args, V, Args1)
	;   Args1 = Args
	),
	I1 is I + 1,
	replace_fields(Fs, I1, Args1, Assigns, Out).

replace_nth(1, [_|T], V, [V|T]) :- !.
replace_nth(N, [X|T], V, [X|Out]) :- N1 is N - 1, replace_nth(N1, T, V, Out).

bind_action(A0, Order, Map, A, Goals0, Goals) :-
	A0 =.. [N|Args0],
	resolve_values(Args0, Order, Map, Args, Goals0, Goals),
	A =.. [N|Args].

rule_diags(Name, Salience, Java, Actions, Src, Diags) :-
	findall(D,
		( Salience =\= 0,
		  format(atom(M), 'rule "~w" uses salience ~w. LPS has no conflict-resolution \c
priority: the rule is translated, the priority is recorded, and firing order may differ \c
(§IV.2)', [Name, Salience]),
		  diag(warning, drools_salience, Src, M, D) ),
		D1),
	findall(D,
		( member(j(L, Why), Java),
		  (   Why = value(VT)
		  ->  format(atom(M), 'rule "~w": `~w` changes working memory with the value `~w`, \c
which is Java the reader does not compute (it reads a variable, an accessor such as \c
`$p.getName()` or `$t.intValue()`, and arithmetic over them): the change is not translated, \c
and the rule performs the external action java_leaf(~q) in its place, which changes nothing \c
in the state (§IV.1)', [Name, L, VT, Name])
		  ;   format(atom(M), 'rule "~w": `~w` is Java, which is not translated: \c
the rule performs the external action java_leaf(~q) in its place, which changes nothing \c
in the state (§IV.1)', [Name, L, Name])
		  ),
		  diag(warning, drools_java_leaf, Src, M, D) ),
		D2),
	findall(D,
		( Actions == [],
		  format(atom(M), 'rule "~w" has no working-memory action: its whole \c
consequence is procedural', [Name]),
		  diag(warning, drools_no_action, Src, M, D) ),
		D3),
	append([D1, D2, D3], Diags).

		 /*******************************
		 *	 the world reading	*
		 *******************************/

/* Working memory is a store of Java objects, and insert, modify and delete
   are what a program does to it. Read as LPS, the same rule base is about
   the world those objects stand for: a Fire in working memory is a fire in
   a room, inserting one is a fire starting, a `modify` of a Sprinkler's
   `on` is the sprinkler turning on. Actions and events in LPS are things
   that happen in the world, not operations on a store, so:

     - each fact type is a fluent over the fields that tell its facts apart.
       A field that every fact of the rule base gives one same value (`new
       Alarm( "house1" )`, which no rule reads) tells none apart: it is left
       out, and a diagnostic says so;
     - a boolean field is a state of its own — `sprinkler_on(Room)`, the
       sprinkler in the room is on — so `on == false` is its negation, and a
       modify of it is the object turning on or off;
     - insert, delete and modify are events named after the change they make
       in the world — `fire_starts`, `alarm_ends`, `sprinkler_turns_on`,
       `order_state_becomes` — never after the operation on working memory;
     - Drools fires an activation once, LPS a rule in every cycle its
       conditions hold. A rule whose one change is an insert is guarded by
       the inserted fact not holding yet — the refraction Drools gives it,
       as a condition anyone can read (`not alarm`). A rule that modifies or
       deletes what it matched guards itself.

   The words. A translator cannot know that an alarm "goes on" and a fire
   "is put out"; the default wording states plainly what holds and what
   happens (`there is a fire in *a room*`, `a fire starts in *a room*`,
   `the sprinkler in *a room* turns on`), and a wording table beside the DRL
   — `<stem>.wording`, one line per fluent or event, keyed by the name this
   reading gives it:

	% Fire.wording
	alarm: an alarm is on
	alarm_starts: an alarm goes on; known as alarm_goes_on

   — gives the words, and the names, a person would choose. drl_templates/2
   hands them to the Logical English writer.
*/

%!	drl_kinds(+File, +ExtraDeclares, -Kinds) is det.
%
%	Kinds: [Type-Field-Kind]: a field's Java type (`boolean`,
%	`object:Room`), from the file's `declare`s and the fact model.
drl_kinds(File, Extra, Kinds) :-
	findall(T-F-K, ( member(declare(T0, Fs), Extra), downcase_atom(T0, T),
			 member(F-K, Fs), K \== plain ), K1),
	drl_text(File, Text),
	split_string(Text, "\n", "", Lines0),
	maplist([L, N]>>normalize_space(string(N), L), Lines0, Lines),
	declared_kinds(Lines, none, K2),
	append(K1, K2, Kinds).

declared_kinds([], _, []).
declared_kinds([L|Ls], Cur, Out) :-
	(   sub_string(L, 0, _, _, "declare ")
	->  declare_name(L, T), declared_kinds(Ls, T, Out)
	;   L == "end"
	->  declared_kinds(Ls, none, Out)
	;   Cur \== none, split_string(L, ":", " ", [FS, KS|_]), FS \== "", KS \== ""
	->  string_lower(FS, FL), atom_string(F, FL),
	    split_string(KS, " ", " ", [K0|_]), atom_string(K, K0),
	    Out = [Cur-F-K|Out1], declared_kinds(Ls, Cur, Out1)
	;   declared_kinds(Ls, Cur, Out)
	).

%	The wording table's lines: w(Name, Text, KnownAs, LineNo).
wording_lines(File, Options, Lines) :-
	(   memberchk(wording_text(T), Options) -> Text = T
	;   memberchk(wording(WF), Options), exists_file(WF)
	->  read_file_to_string(WF, Text, [encoding(utf8)])
	;   file_name_extension(Stem, _, File), file_name_extension(Stem, wording, WF),
	    exists_file(WF)
	->  read_file_to_string(WF, Text, [encoding(utf8)])
	;   Text = ""
	),
	split_string(Text, "\n", "\r", Ls),
	findall(w(Name, Txt, As, N),
		( nth1(N, Ls, L0), normalize_space(string(L), L0),
		  L \== "", \+ sub_string(L, 0, 1, _, "%"), \+ sub_string(L, 0, 1, _, "#"),
		  once(sub_string(L, B, 1, _, ":")),
		  sub_string(L, 0, B, _, N0), normalize_space(atom(Name), N0),
		  B1 is B + 1, sub_string(L, B1, _, 0, R0), normalize_space(string(R), R0),
		  (   sub_string(R, K, _, _, "; known as ")
		  ->  sub_string(R, 0, K, _, Txt0), K1 is K + 11, sub_string(R, K1, _, 0, A0),
		      normalize_space(atom(As), A0)
		  ;   Txt0 = R, As = Name
		  ),
		  normalize_space(string(Txt), Txt0) ),
		Lines).

%!	world_of(+Rules, +Order, +Kinds, +Facts, +WordingLines, +File, -World, -Diags)
%
%	World = world(Shapes, Meanings): shape(Type, Fields, Kept, Bools,
%	Dropped) per type (Kept: the fluent's fields, in the order its
%	wording names them), and m(Default, Name, Arity, Meaning, Text) for
%	every fluent and event the reading may use.
world_of(Rules, Order, Kinds, Facts, WLines, File, world(Shapes, Meanings), Diags) :-
	findall(O, rule_occurrence(Rules, Order, O), Occs0),
	%  The types whose facts the reading knows all of: those given as facts
	%  and those the rules insert. A field of any other type that a
	%  condition compares with a constant is kept: the facts come from
	%  outside the rule base, and `tier == gold` says there are others.
	findall(T, ( member(Fact, Facts), ( atom(Fact) ; compound(Fact) ), functor(Fact, T, _) ), FTs),
	findall(T, ( member(rule(_, _, _, RHS, _), Rules), member(L, RHS),
		     rhs_action(L, Order, A, K), memberchk(K, [insert, insert_logical]),
		     inserted_type(A, T) ), ITs),
	append(FTs, ITs, STs0), sort(STs0, Known),
	findall(T-F, condition_constant(Rules, T, F), Tested0), sort(Tested0, Tested),
	findall(occ(T, F, const(V)),
		( member(Fact, Facts), compound(Fact), Fact =.. [T|Vs], memberchk(T-Fields, Order),
		  nth1(I, Fields, F), nth1(I, Vs, V) ), Occs1),
	append(Occs0, Occs1, Occs),
	findall(T, member(T-_, Order), Types),
	findall(S, ( member(T-Fields, Order), type_shape(T, Fields, Kinds, Types, Occs, Known, Tested, S) ), Shapes),
	findall(M, ( member(S, Shapes), shape_meaning(S, Kinds, Types, M) ), Meanings0),
	Src = src(File, 1, 0, drl),
	apply_wording(WLines, Meanings0, Meanings, Src, WDiags),
	findall(D, ( member(shape(T, _, _, _, Dropped), Shapes), member(F-C, Dropped),
		     format(atom(Msg), 'every ~w has ~w ~q, so the field tells no two of them apart: the reading leaves it out', [T, F, C]),
		     diag(info, drools_field_dropped, Src, Msg, D) ), DDiags),
	append(DDiags, WDiags, Diags).

%	Every value a rule gives a field: const(V), var (bound, compared or
%	taken from a variable) or neg(...) inside a `not` pattern.
rule_occurrence(Rules, Order, Occ) :-
	member(rule(_, _, Body, RHS, _), Rules),
	body_alternatives(Body, Alts), member(Patterns, Alts),
	rule_var_map(Patterns, Map), findall(V, member(V-_, Map), Names),
	(   member(X, Patterns), item_pattern(X, pattern(Kind, _, T, Cs)), member(C, Cs),
	    constraint_occ(C, Names, F, V0),
	    ( Kind == neg -> V = neg(V0) ; V = V0 ),
	    Occ = occ(T, F, V)
	;   member(L, RHS), rhs_action(L, Order, A0, K), memberchk(K, [insert, insert_logical]),
	    A0 =.. [N|Args], atom_concat(insert_, T, N), memberchk(T-Fields, Order),
	    nth1(I, Args, A), nth1(I, Fields, F),
	    value_occ(A, Names, V), Occ = occ(T, F, V)
	;   member(L, RHS), sub_string(L, B, _, _, "modify("),
	    P is B + 7, sub_string(L, P, _, 0, Rest), sub_string(Rest, E, 1, _, ")"),
	    sub_string(Rest, 0, E, _, VarS), normalize_space(atom(Var), VarS),
	    once(( member(X, Patterns), item_pattern(X, pattern(_, Var, T, _)) )),
	    assignments(Rest, Assigns), member(F-A, Assigns),
	    value_occ(A, Names, V), Occ = occ(T, F, V)
	).

%	A field a condition compares with a constant.
condition_constant(Rules, T, F) :-
	member(rule(_, _, Body, _, _), Rules),
	body_alternatives(Body, Alts), member(Patterns, Alts),
	rule_var_map(Patterns, Map), findall(V, member(V-_, Map), Names),
	member(X, Patterns), item_pattern(X, pattern(_, _, T, Cs)), member(C, Cs),
	constraint_occ(C, Names, F, const(_)).

constraint_occ(eq(F, ref(_, _)), _, F, var) :- !.
constraint_occ(eq(F, V), Names, F, O) :- !, value_occ(V, Names, O).
constraint_occ(bind(F, _), _, F, var) :- !.
constraint_occ(cmp(_, F, _), _, F, var).

value_occ(V, Names, var) :- atom(V), memberchk(V, Names), !.
value_occ(V, _, var) :- compound(V), memberchk(V, [jexpr(_, _), ref(_, _), untranslatable(_)]), !.
value_occ(V, _, const(V)).

type_shape(T, Fields, Kinds, Types, Occs, Known, Tested, shape(T, Fields, Kept, Bools, Dropped)) :-
	include(bool_field(T, Kinds, Occs), Fields, Bools),
	subtract(Fields, Bools, Rest),
	(   referenced(T, Kinds, Types), Fields = [Key|_] -> true ; Key = '' ),
	findall(F-C, ( member(F, Rest), F \== Key, constant_field(T, F, Occs, C),
		       ( memberchk(T, Known) -> true ; \+ memberchk(T-F, Tested) ) ), Dropped),
	pairs_keys(Dropped, DFs), subtract(Rest, DFs, Kept0),
	findall(R-F, ( member(F, Kept0), phrase_rank(T, F, Kinds, Types, R) ), RFs),
	msort_stable(RFs, Kept).

%	(sort/4 on the key alone keeps the declared order within a rank)
msort_stable(RFs, Fs) :- sort(1, @=<, RFs, S), pairs_values(S, Fs).

%	A boolean field that is a state of its own: declared boolean, or given
%	nothing but true and false; and never a variable, and never `false`
%	inside a `not` (which would need a negated conjunction).
bool_field(T, Kinds, Occs, F) :-
	(   memberchk(T-F-K, Kinds) -> memberchk(K, [boolean, 'Boolean'])
	;   once(( member(occ(T, F, O), Occs), bare_occ(O, const(V)), memberchk(V, [true, (false)]) )),
	    forall(( member(occ(T, F, O), Occs), bare_occ(O, B) ), ( B = const(V), memberchk(V, [true, (false)]) ))
	),
	\+ ( member(occ(T, F, O), Occs), bare_occ(O, var) ),
	\+ memberchk(occ(T, F, neg(const(false))), Occs).

bare_occ(neg(O), O) :- !.
bare_occ(O, O).

%	A field every occurrence gives one same constant (at least one).
constant_field(T, F, Occs, C) :-
	findall(O, ( member(occ(T, F, O0), Occs), bare_occ(O0, O) ), Os),
	Os = [const(C)|_],
	forall(member(O, Os), O == const(C)).

%	Another type holds this type's facts by reference (`Fire.room` is a
%	Room): its first field is its facts' name, and stays.
referenced(T, Kinds, Types) :-
	(   member(_-_-K, Kinds), atom(K), atom_concat('object:', X0, K),
	    atomic_list_concat(Ps, '.', X0), last(Ps, X1), downcase_atom(X1, T)
	->  true
	;   memberchk(T, Types), member(T2-F-_, Kinds), T2 \== T, F == T
	->  true
	;   fail
	).

		 /*******************************
		 *	      wording		*
		 *******************************/

%	The place a field takes in a sentence: its name (`called *a name*`),
%	where the thing is (`in *a room*`), what it is for (`for *a driver*`),
%	or an attribute (`with band *a band*`), in that order.
phrase_rank(T, F, Kinds, Types, R) :-
	(   F == name -> R = 0
	;   location_word(F) -> R = 1
	;   reference_field(T, F, Kinds, Types, _) -> R = 2
	;   R = 3
	).

location_word(F) :- memberchk(F, [room, location, place, area, zone, building, floor, site, city,
				  country, region, house, office, address, warehouse, store]).

reference_field(T, F, Kinds, Types, X) :-
	(   memberchk(T-F-K, Kinds), atom(K), atom_concat('object:', X0, K)
	->  atomic_list_concat(Ps, '.', X0), last(Ps, X1), downcase_atom(X1, X)
	;   memberchk(F, Types), F \== T, X = F
	).

field_phrase(T, F, Kinds, Types, R, Text) :-
	phrase_rank(T, F, Kinds, Types, R),
	field_words(F, FW),
	(   reference_field(T, F, Kinds, Types, X) -> words_of(X, TW)
	;   memberchk(T-F-K, Kinds), memberchk(K, [boolean, 'Boolean']) -> TW = 'truth value'
	;   TW = FW
	),
	with_article(TW, V),
	(   R =:= 0 -> format(atom(Text), 'called *~w*', [V])
	;   R =:= 1 -> format(atom(Text), 'in *~w*', [V])
	;   R =:= 2 -> format(atom(Text), 'for *~w*', [V])
	;   format(atom(Text), '~w *~w*', [FW, V])
	).

%	The phrases of Fields, joined: `called *a name* in *a room* with band
%	*a band* and level *a level*`.
phrases(T, Fields, Kinds, Types, Text) :-
	findall(R-P, ( member(F, Fields), field_phrase(T, F, Kinds, Types, R, P) ), RPs),
	findall(P, ( member(R-P, RPs), R < 3 ), Front),
	findall(P, member(3-P, RPs), Attrs),
	(   Attrs == [] -> Back = []
	;   Attrs = [A1|As], format(atom(W1), 'with ~w', [A1]),
	    findall(W, ( member(A, As), format(atom(W), 'and ~w', [A]) ), Ws),
	    Back = [W1|Ws]
	),
	append(Front, Back, All),
	atomic_list_concat(All, ' ', Text).

words_of(T, W) :- atomic_list_concat(Ps, '_', T), atomic_list_concat(Ps, ' ', W).
field_words(F, W) :- words_of(F, W).
with_article(W, AW) :-
	sub_atom(W, 0, 1, _, C),
	( memberchk(C, [a, e, i, o, u]) -> A = an ; A = a ),
	format(atom(AW), '~w ~w', [A, W]).

sentence_words(Parts, Text) :-
	exclude(==(''), Parts, Ps), atomic_list_concat(Ps, ' ', Text).

%	Each fluent and event a type may have: m(Default, Name, Arity, Meaning,
%	Text), Name and Text as the wording table leaves them.
shape_meaning(shape(T, _, Kept, Bools, _), Kinds, Types, m(D, D, N, M, Text)) :-
	length(Kept, N),
	words_of(T, TW), with_article(TW, ATW),
	phrases(T, Kept, Kinds, Types, Ph),
	(   D = T, M = exists(T),
	    sentence_words(['there is', ATW, Ph], Text)
	;   atom_concat(T, '_starts', D), M = starts(T),
	    (   Kept = [F1|FR], phrase_rank(T, F1, Kinds, Types, 0)
	    ->  phrases(T, [F1], Kinds, Types, P1), phrases(T, FR, Kinds, Types, PR),
		sentence_words([ATW, P1, starts, PR], Text)
	    ;   sentence_words([ATW, starts, Ph], Text)
	    )
	;   atom_concat(T, '_ends', D), M = ends(T),
	    sentence_words([the, TW, Ph, ends], Text)
	;   member(B, Bools), words_of(B, BW),
	    (   atomic_list_concat([T, '_', B], D), M = state(T, B),
		sentence_words([the, TW, Ph, is, BW], Text)
	    ;   member(V, [true, (false)]), M = set(T, B, V),
		bool_event(T, B, BW, V, D, Verb),
		sentence_words([the, TW, Ph, Verb], Text)
	    )
	;   member(F, Kept), atomic_list_concat([T, '_', F, '_becomes'], D), M = field_becomes(T, F),
	    exclude(==(F), Kept, Others), phrases(T, Others, Kinds, Types, PO),
	    field_words(F, FW),
	    (   reference_field(T, F, Kinds, Types, X) -> words_of(X, VW) ; VW = FW ),
	    with_article(VW, AVW),
	    format(atom(Obj), '*~w*', [AVW]),
	    sentence_words([the, FW, of, the, TW, PO, becomes, Obj], Text)
	;   atom_concat(T, '_changes', D), M = changes(T),
	    sentence_words([the, TW, 'changes to one', Ph], Text)
	).

bool_event(T, on, _, true, D, 'turns on') :- !, atom_concat(T, '_turns_on', D).
bool_event(T, on, _, (false), D, 'turns off') :- !, atom_concat(T, '_turns_off', D).
bool_event(T, B, BW, true, D, V) :- !, atomic_list_concat([T, '_becomes_', B], D), atom_concat('becomes ', BW, V).
bool_event(T, B, BW, (false), D, V) :- atomic_list_concat([T, '_stops_being_', B], D), atom_concat('stops being ', BW, V).

%	The wording table over the defaults: each line names a fluent or event
%	by its default name, and gives its words (as many places as it has) and
%	optionally the name LPS knows it by.
apply_wording(Lines, Ms0, Ms, Src, Diags) :-
	foldl(apply_line(Src), Lines, Ms0-[], Ms-Diags0),
	reverse(Diags0, Diags).

apply_line(Src, w(Name, Text, As, N), Ms0-Ds0, Ms-Ds) :-
	(   select(m(Name, _, Ar, M, _), Ms0, Rest)
	->  placeholders(Text, P),
	    (   P =:= Ar
	    ->  Ms = [m(Name, As, Ar, M, Text)|Rest], Ds = Ds0
	    ;   format(atom(Msg), 'wording line ~w: `~w` has ~w place(s) and ~w has ~w: the default wording is kept', [N, Text, P, Name, Ar]),
		diag(warning, drools_wording, Src, Msg, D), Ms = Ms0, Ds = [D|Ds0]
	    )
	;   format(atom(Msg), 'wording line ~w: nothing in this rule base is called ~w', [N, Name]),
	    diag(warning, drools_wording, Src, Msg, D), Ms = Ms0, Ds = [D|Ds0]
	).

placeholders(Text, P) :-
	atom_codes(Text, Cs), include(==(0'*), Cs, Stars), length(Stars, S), P is S // 2.

		 /*******************************
		 *	 terms of the reading	*
		 *******************************/

wname(world(_, Ms), Default, Name) :- memberchk(m(Default, Name, _, _, _), Ms).

shape_of(world(Shapes, _), T, S) :- S = shape(T, _, _, _, _), memberchk(S, Shapes).

%	A raw fluent (a Drools fact: Type(Field1, ...)) and its shape.
raw_shape(W, F, S, Args) :-
	nonvar(F), \+ F = not(_), functor(F, T, N),
	shape_of(W, T, S), S = shape(T, Fields, _, _, _), length(Fields, N),
	F =.. [_|Args].

field_arg(shape(_, Fields, _, _, _), Args, F, A) :- nth1(I, Fields, F), nth1(I, Args, A).

kept_args(S, Args, K) :- S = shape(_, _, Kept, _, _), kept_args_(Kept, S, Args, K).
kept_args_([], _, _, []).
kept_args_([F|Fs], S, Args, [A|As]) :- field_arg(S, Args, F, A), kept_args_(Fs, S, Args, As).

named(W, Default, Args, Term) :- wname(W, Default, Name), Term =.. [Name|Args].

exists_fluent(W, shape(T, _, _, _, _), K, F) :- named(W, T, K, F).
state_fluent(W, shape(T, _, _, _, _), B, K, F) :- atomic_list_concat([T, '_', B], D), named(W, D, K, F).
starts_event(W, shape(T, _, _, _, _), K, E) :- atom_concat(T, '_starts', D), named(W, D, K, E).
ends_event(W, shape(T, _, _, _, _), K, E) :- atom_concat(T, '_ends', D), named(W, D, K, E).
set_event(W, shape(T, _, _, _, _), B, V, K, E) :- bool_event(T, B, B, V, D, _), named(W, D, K, E).

%!	world_fluents(+World, -Templates) is det.
world_fluents(W, Fluents) :-
	W = world(Shapes, _),
	findall(F, ( member(S, Shapes), S = shape(_, _, Kept, Bools, _), length(Kept, N), length(K, N),
		     ( exists_fluent(W, S, K, F) ; member(B, Bools), state_fluent(W, S, B, K, F) ) ),
		Fluents).

%	The conditions of a rule, as states of the world. (Built from the
%	rule's own arguments: no copy, so the variables stay shared.)
world_conditions(_, [], []).
world_conditions(W, [C|Cs], Out) :-
	world_condition(W, C, Ws),
	append(Ws, Rest, Out),
	world_conditions(W, Cs, Rest).

%	`not` over a pattern with a comparison: the negation of a conjunction.
world_condition(W, holds(not(L), T), [holds(not(WL), T)]) :-
	is_list(L), !,
	world_conditions(W, L, WL).
%	An accumulate: findall inside holds, and the reduction.
world_condition(W, acc_lit(Fn, A, Inner, R, Goals, T), [holds(findall(A, WInner, L), T), Reduce|Goals]) :- !,
	world_conditions(W, Inner, WInner),
	reduction(Fn, L, R, Reduce).
world_condition(W, holds(not(F), T), [holds(not(G), T)]) :-
	raw_shape(W, F, S, Args), !,
	kept_args(S, Args, K),
	S = shape(_, _, _, Bools, _),
	(   member(B, Bools), field_arg(S, Args, B, V), V == true
	->  state_fluent(W, S, B, K, G)
	;   exists_fluent(W, S, K, G)
	).
world_condition(W, holds(F, T), Lits) :-
	raw_shape(W, F, S, Args), !,
	kept_args(S, Args, K),
	S = shape(_, _, _, Bools, _),
	state_literals(Bools, W, S, Args, K, T, States),
	(   member(B, Bools), field_arg(S, Args, B, V), V == true
	->  Lits = States
	;   exists_fluent(W, S, K, E), Lits = [holds(E, T)|States]
	).
world_condition(_, C, [C]).

reduction(sum, L, R, sum_list(L, R)).
reduction(count, L, R, length(L, R)).
reduction(min, L, R, min_list(L, R)).
reduction(max, L, R, max_list(L, R)).

state_literals([], _, _, _, _, _, []).
state_literals([B|Bs], W, S, Args, K, T, Out) :-
	field_arg(S, Args, B, V),
	(   V == true -> state_fluent(W, S, B, K, F), Out = [holds(F, T)|Out1]
	;   V == (false) -> state_fluent(W, S, B, K, F), Out = [holds(not(F), T)|Out1]
	;   Out = Out1
	),
	state_literals(Bs, W, S, Args, K, T, Out1).

%	The changes of a consequence (A-modify(Old, New), A-retract(Gone),
%	A-Line for an insert) as events and their laws.
world_changes(_, _, [], [], []).
world_changes(W, Order, [A-What|As], Events, Laws) :-
	change_events(W, Order, A, What, Es, Ls),
	world_changes(W, Order, As, Es1, Ls1),
	append(Es, Es1, Events), append(Ls, Ls1, Laws).

change_events(W, Order, A, What, Es, Ls) :-
	(   What = retract(Gone), raw_shape(W, Gone, S, Args)
	->  kept_args(S, Args, K), ends_event(W, S, K, E), Es = [E], event_laws(W, E, Ls)
	;   What = modify(Old, New), raw_shape(W, Old, S, OArgs)
	->  New =.. [_|NArgs], modify_events(W, S, OArgs, NArgs, Es, Ls)
	;   string(What), A =.. [N|RArgs], atom_concat(retract_, T, N),
	    type_fact(Order, T, RArgs, F), raw_shape(W, F, S, Args)
	->  kept_args(S, Args, K), ends_event(W, S, K, E), Es = [E], event_laws(W, E, Ls)
	;   string(What), inserted_fact(A, Order, F), raw_shape(W, F, S, Args)
	->  kept_args(S, Args, K), starts_event(W, S, K, E),
	    S = shape(_, _, _, Bools, _),
	    findall(B, ( member(B, Bools), field_arg(S, Args, B, V), V == true ), Ons),
	    set_events(Ons, W, S, K, OnEs),
	    Es = [E|OnEs],
	    maplist(event_laws(W), Es, LLs), append(LLs, Ls)
	;   Es = [], Ls = []
	).

set_events([], _, _, _, []).
set_events([B|Bs], W, S, K, [E|Es]) :- set_event(W, S, B, true, K, E), set_events(Bs, W, S, K, Es).

%	`insert_type(a, b)` -> type(a, b), the fields in their order (a
%	constructor with fewer arguments leaves the rest unbound).
inserted_fact(A, Order, F) :-
	A =.. [N|Args], atom_concat(insert_, T, N),
	type_fact(Order, T, Args, F).

%	(a `retract(new Alarm(yes))`, as LPS2's own restated rule bases write
%	it, names its fact the same way)
type_fact(Order, T, Args, F) :-
	memberchk(T-Fields, Order),
	length(Fields, Len), functor(F, T, Len), F =.. [_|FArgs],
	prefix_unify(Args, FArgs).

prefix_unify([], _).
prefix_unify([A|As], [A|Bs]) :- !, prefix_unify(As, Bs).
prefix_unify(_, []).

%	A modify: each boolean it sets is the object turning on (or off); a
%	field it changes is that field becoming the new value; several, the
%	object changing.
modify_events(W, S, OArgs, NArgs, Es, Ls) :-
	S = shape(_, Fields, Kept, Bools, _),
	findall(I, ( nth1(I, Fields, _), nth1(I, OArgs, O), nth1(I, NArgs, N), O \== N ), Changed),
	findall(F, ( member(I, Changed), nth1(I, Fields, F) ), CFs),
	kept_args(S, NArgs, KN), kept_args(S, OArgs, KO),
	findall(B-V, ( member(B, CFs), memberchk(B, Bools), field_arg(S, NArgs, B, V), nonvar(V) ), BVs),
	bool_changes(BVs, W, S, KN, BEs),
	intersection(CFs, Kept, KFs),
	exists_fluent(W, S, KO, OldF),
	(   KFs == [] -> FEs = [], FLs = []
	;   KFs = [F]
	->  exclude(==(F), Kept, Others), kept_args_(Others, S, NArgs, OthersA),
	    field_arg(S, NArgs, F, NV), field_arg(S, OArgs, F, OV),
	    append(OthersA, [NV], EArgs),
	    S = shape(T0, _, _, _, _), atomic_list_concat([T0, '_', F, '_becomes'], D),
	    named(W, D, EArgs, E),
	    FEs = [E], FLs = [updated(happens(E, _, _), OldF, OV-NV, [])]
	;   S = shape(T1, _, _, _, _), atom_concat(T1, '_changes', D1),
	    named(W, D1, KN, E),
	    findall(O, ( member(F2, KFs), field_arg(S, OArgs, F2, O) ), Olds),
	    findall(N, ( member(F2, KFs), field_arg(S, NArgs, F2, N) ), News),
	    FEs = [E], FLs = [updated(happens(E, _, _), OldF, Olds-News, [])]
	),
	maplist(event_laws(W), BEs, BLs), append(BLs, BLaws),
	append(BEs, FEs, Es), append(BLaws, FLs, Ls).

bool_changes([], _, _, _, []).
bool_changes([B-V|BVs], W, S, K, [E|Es]) :- set_event(W, S, B, V, K, E), bool_changes(BVs, W, S, K, Es).

%!	event_laws(+World, +Event, -Laws) is det.
%
%	What an event of the reading initiates and terminates: a thing
%	starting is there; a thing ending is gone, with every state it was in;
%	turning on is being on, and turning off not. (A field becoming a value
%	needs the value it had: modify_events/6.)
event_laws(W, E, Laws) :-
	W = world(_, Ms), functor(E, Name, N), E =.. [_|K],
	( memberchk(m(_, Name, N, M, _), Ms) -> true ; M = none ),
	(   M = starts(T) -> shape_of(W, T, S), exists_fluent(W, S, K, F),
	    Laws = [initiated(happens(E, _, _), F, [])]
	;   M = ends(T) -> shape_of(W, T, S), exists_fluent(W, S, K, F),
	    S = shape(_, _, _, Bools, _),
	    findall(B, member(B, Bools), Bs),
	    state_ends(Bs, W, S, K, E, SLs),
	    Laws = [terminated(happens(E, _, _), F, [])|SLs]
	;   M = set(T, B, true) -> shape_of(W, T, S), state_fluent(W, S, B, K, F),
	    Laws = [initiated(happens(E, _, _), F, [])]
	;   M = set(T, B, false) -> shape_of(W, T, S), state_fluent(W, S, B, K, F),
	    Laws = [terminated(happens(E, _, _), F, [])]
	;   Laws = []
	).

state_ends([], _, _, _, _, []).
state_ends([B|Bs], W, S, K, E, [terminated(happens(E, _, _), F, [])|Ls]) :-
	state_fluent(W, S, B, K, F), state_ends(Bs, W, S, K, E, Ls).

%	Drools' refraction, as a condition: a rule whose one change is an
%	insert does not fire while the fact it inserts already holds (unless a
%	`not` of its own says so already).
refraction_guard(W, Order, Actions0, T, Conds0, Conds) :-
	%  (no findall/3: it copies, and the guard must share the action's
	%  variables — a copy made every insert with an argument unguarded)
	(   Actions0 = [A-L], string(L),
	    rhs_action(L, Order, _, K), memberchk(K, [insert, insert_logical]),
	    inserted_fact(A, Order, F), raw_shape(W, F, S, Args),
	    kept_args(S, Args, Ks), exists_fluent(W, S, Ks, G),
	    \+ ( member(holds(not(G0), _), Conds0), \+ is_list(G0), subsumes_term(G0, G) )
	->  append(Conds0, [holds(not(G), T)], Conds)
	;   Conds = Conds0
	).

%!	drl_world_facts(+World, +Facts, -Fluents) is det.
%
%	Drools facts (Type(Field1, ...), an object-valued field by the object's
%	name) as the reading's fluents: `sprinkler(kitchen, true)` is
%	sprinkler(kitchen) and sprinkler_on(kitchen).
drl_world_facts(W, Facts, Fluents) :-
	foldl(world_fact(W), Facts, [], Rev),
	reverse(Rev, Fluents).

world_fact(W, Fact, Acc, Out) :-
	(   raw_shape(W, Fact, S, Args)
	->  kept_args(S, Args, K), exists_fluent(W, S, K, E),
	    S = shape(_, _, _, Bools, _),
	    findall(F, ( member(B, Bools), field_arg(S, Args, B, V), V == true, state_fluent(W, S, B, K, F) ), Fs),
	    reverse([E|Fs], RFs), append(RFs, Acc, Out)
	;   Out = [Fact|Acc]
	).

%!	drl_driver_events(+World, +Op, +Fact, -Events) is det.
%
%	What a driver's insert (Op = insert) or delete (delete) of a Drools
%	fact is in the world: the thing starting (and turning on), or ending.
drl_driver_events(W, Op, Fact, Events) :-
	raw_shape(W, Fact, S, Args), kept_args(S, Args, K),
	(   Op == insert
	->  starts_event(W, S, K, E),
	    S = shape(_, _, _, Bools, _),
	    findall(B, ( member(B, Bools), field_arg(S, Args, B, V), V == true ), Ons),
	    set_events(Ons, W, S, K, OnEs),
	    Events = [E|OnEs]
	;   ends_event(W, S, K, E), Events = [E]
	).

%!	drl_event_laws(+World, +Event, -Laws) is det.
drl_event_laws(W, E, Laws) :- event_laws(W, E, Laws).

%!	drl_templates(+World, -Templates) is det.
%
%	The wording of every fluent and event the reading may use:
%	template(Name/Arity, Kind, Text), Kind fluent or event, Text with its
%	places marked as Logical English does (`there is a fire in *a room*`).
drl_templates(world(_, Ms), Templates) :-
	findall(template(Name/N, Kind, Text),
		( member(m(_, Name, N, M, Text), Ms),
		  ( memberchk(M, [exists(_), state(_, _)]) -> Kind = fluent ; Kind = event ) ),
		Templates).

%!	drl_meaning(+World, +NameArity, -Meaning) is semidet.
%
%	exists(T), state(T, B), starts(T), ends(T), set(T, B, V),
%	field_becomes(T, F) or changes(T).
drl_meaning(world(_, Ms), Name/N, M) :- memberchk(m(_, Name, N, M, _), Ms).

%!	drl_initially_example(+World, +Terms, -Text) is det.
%
%	An `initially` line for this rule base's own fluents (Terms: the
%	reading's terms, whose intensional fluents are left out), each argument
%	named after its field — `initially customer(Name, Tier), order(Customer,
%	Size).` — for the header of a converted program to show the shape its
%	facts take (a boolean field its own fluent, a field left out gone).
%	'' when the rule base has no fluents.
drl_initially_example(W, Terms, Text) :-
	W = world(Shapes, _),
	findall(N/A, ( member(T0, Terms), ( T0 = t(T, _) -> true ; T = T0 ),
		       nonvar(T), T = l_int(holds(H, _), _), functor(H, N, A) ), Ints),
	findall(S, ( member(Sh, Shapes), Sh = shape(_, _, Kept, Bools, _),
		     findall(A, ( member(F, Kept), field_placeholder(F, A) ), As),
		     (   exists_fluent(W, Sh, As, Fl)
		     ;   member(B, Bools), state_fluent(W, Sh, B, As, Fl)
		     ),
		     Fl =.. [N|Args], length(Args, Ar), \+ memberchk(N/Ar, Ints),
		     (   Args == [] -> format(atom(S), '~w', [N])
		     ;   atomic_list_concat(Args, ', ', AT), format(atom(S), '~w(~w)', [N, AT])
		     ) ),
		Ss),
	(   Ss == [] -> Text = ''
	;   atomic_list_concat(Ss, ', ', L), format(atom(Text), 'initially ~w.', [L])
	).

field_placeholder(F, A) :-
	atomic_list_concat(Ps, '_', F),
	maplist([P, Q]>>( sub_atom(P, 0, 1, _, C), upcase_atom(C, U), sub_atom(P, 1, _, 0, R), atom_concat(U, R, Q) ), Ps, Qs),
	atomic_list_concat(Qs, A).
