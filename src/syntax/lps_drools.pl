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
 *
 * §IV.1's boundary, stated rather than discovered: **the right-hand side of a
 * Drools rule is Java**, and Java is not transpiled. A statement this module
 * does not recognise becomes an *external action* — `java_leaf/2`, which the
 * engine treats as an action with no causal law — and a diagnostic naming the
 * rule and the statement. That is the difference between a transpiler you can
 * trust on a real rule base and one that quietly drops half of it.
 *
 * Two semantic gaps that are reported, not papered over (§IV.5):
 *
 *   * **salience**. Drools resolves conflicts by an operational priority; LPS
 *     has no equivalent and is not supposed to. A rule with a salience gets a
 *     warning, and the priority is recorded in reactive_rule/3 where the
 *     engine can at least see it.
 *   * **truth maintenance** (`insertLogical`). A logically-inserted fact is
 *     retracted when its support goes away, which is an *intensional* fluent
 *     rather than a causal law. Recognised, warned about, and translated as
 *     an intensional fluent when the support is a single pattern.
 */

:- module(lps_drools, [
	drl_to_internal/3,       % +File, -Terms, -Diags
	drl_to_internal/4,       % +File, +Options, -Terms, -Diags
	drl_reading/3,           % +File, +Options, -Reading
	drl_parse/3,             % +File, -Rules, -Declares
	drl_world_facts/3,       % +World, +Facts, -Fluents
	drl_driver_events/4,     % +World, +Op, +Fact, -Events
	drl_event_laws/3,        % +World, +Event, -Laws
	drl_templates/2,         % +World, -Templates
	drl_meaning/3            % +World, +Name/Arity, -Meaning
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
%
%	Rules are rule(Name, Salience, Patterns, RHS, Line); Declares are
%	declare(Type, Fields).
drl_parse(File, Rules, Declares) :-
	drl_text(File, Text),
	split_string(Text, "\n", "", Lines),
	parse_lines(Lines, 1, [], Rules, Declares).

parse_lines([], _, _, [], []).
parse_lines([L|Ls], N, Acc, Rules, Declares) :-
	normalize_space(string(T), L),
	N1 is N + 1,
	(   sub_string(T, 0, _, _, "rule ")
	->  rule_name(T, Name),
	    collect_until_end(Ls, Rest, Body0, N1, N2),
	    %  `rule RaiseAlarm when` (real DRL puts `when` on the rule's line)
	    (   ( sub_string(T, _, _, 0, " when") ; sub_string(T, _, _, _, " when ") )
	    ->  Body = ["when"|Body0]
	    ;   Body = Body0
	    ),
	    rule_of(Name, Body, N, Rule),
	    parse_lines(Rest, N2, Acc, Rules0, Declares),
	    Rules = [Rule|Rules0]
	;   sub_string(T, 0, _, _, "declare ")
	->  declare_name(T, Type),
	    collect_until_end(Ls, Rest, Body, N1, N2),
	    fields_of(Body, Fields),
	    parse_lines(Rest, N2, Acc, Rules, Declares0),
	    Declares = [declare(Type, Fields)|Declares0]
	;   parse_lines(Ls, N1, Acc, Rules, Declares)
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

declare_name(T, Type) :-
	split_string(T, " ", " ", Parts),
	( Parts = [_, S|_] -> string_lower(S, L), atom_string(Type, L) ; Type = unknown ).

fields_of(Lines, Fields) :-
	findall(F, ( member(L, Lines), split_string(L, ":", " ", [FS|_]),
		     FS \== "", string_lower(FS, LF), atom_string(F, LF) ), Fields).

%	when … then … — everything between is the condition, everything after
%	is the (Java) consequence.
rule_of(Name, Body, Line, rule(Name, Salience, Patterns, RHS, Line)) :-
	salience_of(Body, Salience),
	split_when_then(Body, When, Then),
	patterns_of(When, Patterns),
	join_braces(Then, RHS).

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

salience_of(Body, S) :-
	(   member(L, Body), sub_string(L, B, _, _, "salience")
	->  Pos is B + 8, sub_string(L, Pos, _, 0, R),
	    normalize_space(string(R1), R),
	    ( number_string(S, R1) -> true ; S = 0 )
	;   S = 0
	).

split_when_then(Body, When, Then) :-
	(   nth0(I, Body, "when")
	->  J is I + 1, length(Pre, J), append(Pre, Rest, Body),
	    (	nth0(K, Rest, "then")
	    ->	length(When, K), append(When, [_|Then], Rest)
	    ;	When = Rest, Then = []
	    )
	;   When = [], Then = Body
	).

/* A pattern is `Var : Type( constraints )`, `Type( constraints )`,
   `not Type( … )` or `exists Type( … )`.
 *
 * DRL separates patterns by *line*, not by comma — the commas inside the
 * parentheses separate a pattern's own constraints. So lines are joined only
 * while their parentheses are unbalanced, which is how a pattern wrapped over
 * three lines stays one pattern.
 */
patterns_of(Lines, Patterns) :-
	join_wrapped(Lines, Chunks0),
	findall(C, ( member(X, Chunks0), normalize_space(atom(C), X), C \== '',
		     C \== 'and' ), Chunks),
	findall(P, ( member(C, Chunks), pattern_of(C, P) ), Patterns).

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

%	Split on top-level commas — the ones outside parentheses, since a
%	pattern's own constraints are comma-separated inside them.
split_patterns(S, Chunks) :-
	atom_codes(S, Cs),
	split_top(Cs, 0, [], Chunks0),
	findall(C, ( member(X, Chunks0), atom_codes(A, X),
		     normalize_space(atom(C), A), C \== '' ), Chunks).

split_top([], _, Acc, [Out]) :- reverse(Acc, Out).
split_top([C|Cs], D, Acc, Out) :-
	(   C =:= 0'( -> D1 is D + 1, split_top(Cs, D1, [C|Acc], Out)
	;   C =:= 0') -> D1 is D - 1, split_top(Cs, D1, [C|Acc], Out)
	;   C =:= 0',, D =:= 0
	->  reverse(Acc, Chunk), split_top(Cs, D, [], Rest), Out = [Chunk|Rest]
	;   split_top(Cs, D, [C|Acc], Out)
	).

pattern_of(Chunk, pattern(Kind, Var, Type, Constraints)) :-
	atom_string(Chunk, S0),
	strip_semicolon(S0, S),
	(   quantified(S, "not", S1) -> Kind = neg
	;   quantified(S, "exists", S1) -> Kind = pos
	;   Kind = pos, S1 = S
	),
	(   sub_string(S1, B, 1, _, ":"), sub_string(S1, 0, B, _, V0),
	    normalize_space(string(VS), V0), VS \== "", \+ sub_string(VS, _, _, _, "(")
	->  atom_string(Var, VS), Bp is B + 1, sub_string(S1, Bp, _, 0, S2)
	;   Var = '', S2 = S1
	),
	sub_string(S2, P, 1, _, "("), !,
	sub_string(S2, 0, P, _, T0), normalize_space(string(TS), T0),
	string_lower(TS, TL), atom_string(Type, TL),
	Pp is P + 1, sub_string(S2, Pp, _, 1, Inner0),
	normalize_space(string(Inner), Inner0),
	constraints_of(Inner, Constraints).

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

constraints_of("", []) :- !.
constraints_of(S, Constraints) :-
	atom_codes(S, Cs), split_top(Cs, 0, [], Parts),
	findall(C, ( member(P, Parts), atom_codes(A, P), normalize_space(atom(N), A),
		     N \== '', constraint_of(N, C) ), Constraints).

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
	clean_field(F0, Field), clean_var(V0, Var).
constraint_of(A, other(A)).

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
	;   downcase_atom(N, V)
	).

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
	drl_parse(File, Rules, Declares0),
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
	findall(T-D, ( member(R, Rules), rule_terms(R, Order, World, File, T, D) ), Pairs),
	findall(T, member(T-_, Pairs), Ts0), append(Ts0, RuleTerms),
	findall(D, member(_-D, Pairs), Ds0), append(Ds0, RuleDiags),
	%  Declarations come from the *translated* terms, not from a second parse
	%  of the right-hand sides: `modify( s ) { … }` names a variable, and
	%  re-deriving the action from it declared `modify_s` while the rules
	%  used `modify_sprinkler`.
	declarations(World, RuleTerms, File, DeclTerms),
	append(DeclTerms, RuleTerms, Terms),
	append(WDiags, RuleDiags, Diags).

field_name_only(F-_, F) :- !.
field_name_only(F, F).

/* Drools facts are Java objects; LPS fluents are terms. So a type's fields
   need an *order*, and it comes from a `declare` block when there is one and
   from the union of the fields the rules mention otherwise. Inferring it is
   not a guess about semantics — the order is arbitrary and internal — but it
   does mean two files about the same type must be translated together.
*/
field_order(Rules, Declares, Order) :-
	findall(Type-Fields,
		( member(declare(Type, Fields), Declares) ),
		FromDeclares),
	findall(Type-Fields,
		( member(rule(_, _, Patterns, _, _), Rules),
		  member(pattern(_, _, Type, _), Patterns),
		  \+ memberchk(Type-_, FromDeclares),
		  findall(F, ( member(rule(_, _, Ps, _, _), Rules),
			       member(pattern(_, _, Type, Cs), Ps),
			       member(C, Cs), constraint_field(C, F) ), Fs0),
		  sort(Fs0, Fields) ),
		FromRules0),
	dedupe_keys(FromRules0, FromRules),
	append(FromDeclares, FromRules, Order).

dedupe_keys([], []).
dedupe_keys([K-V|T], [K-V|Out]) :- exclude_key(K, T, T1), dedupe_keys(T1, Out).
exclude_key(_, [], []).
exclude_key(K, [K2-V|T], Out) :-
	( K == K2 -> Out = Out1 ; Out = [K2-V|Out1] ),
	exclude_key(K, T, Out1).

constraint_field(eq(F, _), F).
constraint_field(bind(F, _), F).
constraint_field(cmp(_, F, _), F).

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

/* One rule → one reactive rule, plus the causal laws its right-hand side
   implies, in the world reading (below): the patterns are states of the
   world, and each change the consequence makes to working memory is an
   event with its `initiates`/`terminates`/`updates`.

   All the patterns of a Drools rule match ONE state of working memory, so
   they share one time T; the consequence's actions start at T, together —
   a DRL consequence is one block — and so does the Logical English, which
   then needs no times at all (le_lps_surface.md §3.1).
*/
rule_terms(rule(Name, Salience, Patterns, RHS, Line), Order, World, File, Terms, Diags) :-
	Src = src(File, Line, 0, drl),
	%  One variable map per rule: `Fire(room : room)` binds `room`, and the
	%  `room == room` of the next pattern refers to *that* variable. Without
	%  the map each pattern gets its own, and the rule says "a fire and a
	%  sprinkler, anywhere" — which is not what it says.
	rule_var_map(Patterns, RHS, Map),
	b_setval(drl_rule_patterns, []),
	maplist(pattern_literal(Order, Map, T), Patterns, Conds0),
	%  `room == s.room` (a field of another pattern's fact) and `age > 25`
	%  (a comparison): after every pattern has its fluent
	resolve_references(Patterns, Conds0, Order, Map, Extra),
	append(Conds0, Extra, Conds1),
	rhs_actions(RHS, Order, Map, Patterns, Actions0),
	%  No findall/3 anywhere near these: it copies, and a copied action no
	%  longer shares the rule's variables with the antecedent that bound
	%  them. `insert(new Sprinkler(room, on))` would insert a sprinkler in
	%  *some* room rather than in the burning one.
	world_conditions(World, Conds1, Conds2),
	world_changes(World, Order, Actions0, Events, Laws),
	refraction_guard(World, Order, Actions0, T, Conds2, Conds),
	(   Events == []
	->  Cons = [happens(java_leaf(Name), T, _)]
	;   happens_from(Events, T, Cons)
	),
	(   Salience =:= 0
	->  Rule = reactive_rule(Conds, Cons)
	;   Rule = reactive_rule(Conds, Cons, Salience)
	),
	laws_at(Laws, Src, Effects),
	Terms = [t(Rule, Src)|Effects],
	keys_of(Actions0, Actions),
	rule_diags(Name, Salience, RHS, Actions, Src, Diags).

happens_from([], _, []).
happens_from([E|Es], T, [happens(E, T, _)|Out]) :- happens_from(Es, T, Out).

laws_at([], _, []).
laws_at([L|Ls], Src, [t(L, Src)|Out]) :- laws_at(Ls, Src, Out).

rule_var_map(Patterns, RHS, Map) :-
	findall(V, ( member(pattern(_, _, _, Cs), Patterns), member(bind(_, V), Cs) ), Vs0),
	findall(V, ( member(pattern(_, V, _, _), Patterns), V \== '' ), Vs1),
	append(Vs0, Vs1, Vs2), sort(Vs2, Vars),
	findall(V-_, member(V, Vars), Map),
	ignore(RHS = RHS).

pattern_literal(Order, Map, T, pattern(Kind, Var, Type, Constraints), Literal) :-
	fluent_term(Type, Constraints, Order, Map, F),
	(   Var \== '', nb_current(drl_rule_patterns, PFs0) -> b_setval(drl_rule_patterns, [Var-Type-F|PFs0])
	;   true
	),
	( Kind == neg -> Literal = holds(not(F), T) ; Literal = holds(F, T) ).

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
constraint_value(eq(_, ref(_, _)), _, _) :- !.           % resolve_references/5
constraint_value(cmp(_, _, _), _, _) :- !.
constraint_value(eq(_, V), Map, Slot) :-
	( memberchk(V-Var, Map) -> Slot = Var ; Slot = V ).
constraint_value(bind(_, V), Map, Slot) :-
	( memberchk(V-Var, Map) -> Slot = Var ; true ).

%	A reference to a field of another pattern's fact unifies the two slots;
%	a comparison becomes a condition on the slot. The fluents are the
%	patterns' own (Conds), so no copy is made anywhere.
resolve_references([], [], _, _, []).
resolve_references([pattern(Kind, _, Type, Cs)|Ps], [Lit|Ls], Order, Map, Extra) :-
	Lit = holds(F0, _), ( F0 = not(F) -> true ; F = F0 ),
	( memberchk(Type-Fields, Order) -> true ; Fields = [] ),
	refs_of(Cs, Fields, F, Kind, Order, Map, Ps, Ls, E1),
	resolve_references(Ps, Ls, Order, Map, E2),
	append(E1, E2, Extra).

refs_of([], _, _, _, _, _, _, _, []).
refs_of([C|Cs], Fields, F, Kind, Order, Map, Ps, Ls, Extra) :-
	(   C = eq(Field, ref(Obj, Fld)), nth1(I, Fields, Field)
	->  ( ref_slot(Obj, Fld, Order, Map, Slot) -> arg(I, F, Slot) ; true ), Extra = Extra1
	;   C = cmp(Op, Field, V0), nth1(I, Fields, Field), Kind == pos
	->  arg(I, F, Slot),
	    value_slot(V0, Order, Map, V),
	    cmp_goal(Op, Slot, V, G),
	    Extra = [G|Extra1]
	;   Extra = Extra1
	),
	refs_of(Cs, Fields, F, Kind, Order, Map, Ps, Ls, Extra1).

%	The patterns of the rule being built, by their variable (set by
%	rule_terms/5 through b_setval, so no copy is made).
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
	( sub_string(Rest, E, 1, _, ")") -> sub_string(Rest, 0, E, _, Inner) ; Inner = Rest ),
	normalize_space(string(I2), Inner),
	( sub_string(I2, 0, 4, _, "new ") -> sub_string(I2, 4, _, 0, I3) ; I3 = I2 ),
	(   sub_string(I3, P2, 1, _, "(")
	->  sub_string(I3, 0, P2, _, T0), P3 is P2 + 1,
	    sub_string(I3, P3, _, 0, A0),
	    split_string(A0, ",", " ()", Args0),
	    findall(A, ( member(S, Args0), S \== "", clean_value(S, A) ), Args)
	;   T0 = I3, Args = []
	),
	string_lower(T0, TL), atom_string(Type, TL).

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

rhs_actions([], _, _, _, []).
rhs_actions([L|Ls], Order, Map, Patterns, Out) :-
	(   modify_action(L, Order, Map, Patterns, A, Old, New)
	->  Out = [A-modify(Old, New)|Rest]
	;   retract_action(L, Order, Map, Patterns, A, Gone)
	->  Out = [A-retract(Gone)|Rest]
	;   rhs_action(L, Order, A0, _)
	->  bind_action(A0, Map, A), Out = [A-L|Rest]
	;   Out = Rest
	),
	rhs_actions(Ls, Order, Map, Patterns, Rest).

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
modify_action(Line, Order, Map, Patterns, Action, Old, New) :-
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
	assignments(Rest, Assigns),
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

%	`{ f = v, g = w }` → [f-v, g-w]; `{ setOn( true ) }` (real DRL's setters)
%	→ [on-true].
assignments(S, Assigns) :-
	(   sub_string(S, B, 1, _, "{"), sub_string(S, A, 1, _, "}"), A > B
	->  Start is B + 1, Len is A - Start,
	    sub_string(S, Start, Len, _, Inner),
	    split_string(Inner, ",;", " ", Parts),
	    findall(F-V, ( member(Part, Parts), Part \== "", assignment(Part, F, V) ), Assigns)
	;   Assigns = []
	).

assignment(Part, F, V) :-
	(   split_string(Part, "=", " ", [FS, VS]), \+ sub_string(FS, _, _, _, "(")
	->  string_lower(FS, FL), atom_string(F, FL), clean_value(VS, V)
	;   normalize_space(string(P), Part),
	    sub_string(P, 0, 3, _, "set"), sub_string(P, B, 1, _, "("), sub_string(P, _, 1, 0, ")"),
	    Len is B - 3, sub_string(P, 3, Len, _, FS),
	    string_lower(FS, FL), atom_string(F, FL),
	    B1 is B + 1, sub_string(P, B1, _, 1, VS), clean_value(VS, V)
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

bind_action(A0, Map, A) :-
	A0 =.. [N|Args0],
	map_args(Args0, Map, Args),
	A =.. [N|Args].

map_args([], _, []).
map_args([Arg|As], Map, [X|Xs]) :-
	( memberchk(Arg-V, Map) -> X = V ; X = Arg ),
	map_args(As, Map, Xs).

rule_diags(Name, Salience, RHS, Actions, Src, Diags) :-
	findall(D,
		( Salience =\= 0,
		  format(atom(M), 'rule "~w" uses salience ~w. LPS has no conflict-resolution \c
priority: the rule is translated, the priority is recorded, and firing order may differ \c
(§IV.2)', [Name, Salience]),
		  diag(warning, drools_salience, Src, M, D) ),
		D1),
	findall(D,
		( member(L, RHS), \+ rhs_action(L, [], _, _), L \== "",
		  \+ sub_string(L, 0, _, _, "//"),
		  format(atom(M), 'rule "~w": `~w` is a procedural leaf and is not \c
transpiled; it becomes an external action (§IV.1)', [Name, L]),
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
	findall(occ(T, F, const(V)),
		( member(Fact, Facts), compound(Fact), Fact =.. [T|Vs], memberchk(T-Fields, Order),
		  nth1(I, Fields, F), nth1(I, Vs, V) ), Occs1),
	append(Occs0, Occs1, Occs),
	findall(T, member(T-_, Order), Types),
	findall(S, ( member(T-Fields, Order), type_shape(T, Fields, Order, Kinds, Types, Occs, S) ), Shapes),
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
	member(rule(_, _, Patterns, RHS, _), Rules),
	rule_var_map(Patterns, RHS, Map), findall(V, member(V-_, Map), Names),
	(   member(pattern(Kind, _, T, Cs), Patterns), member(C, Cs),
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
	    memberchk(pattern(_, Var, T, _), Patterns),
	    assignments(Rest, Assigns), member(F-A, Assigns),
	    value_occ(A, Names, V), Occ = occ(T, F, V)
	).

constraint_occ(eq(F, ref(_, _)), _, F, var) :- !.
constraint_occ(eq(F, V), Names, F, O) :- !, value_occ(V, Names, O).
constraint_occ(bind(F, _), _, F, var) :- !.
constraint_occ(cmp(_, F, _), _, F, var).

value_occ(V, Names, var) :- atom(V), memberchk(V, Names), !.
value_occ(V, _, const(V)).

type_shape(T, Fields, _Order, Kinds, Types, Occs, shape(T, Fields, Kept, Bools, Dropped)) :-
	include(bool_field(T, Kinds, Occs), Fields, Bools),
	subtract(Fields, Bools, Rest),
	(   referenced(T, Kinds, Types), Fields = [Key|_] -> true ; Key = '' ),
	findall(F-C, ( member(F, Rest), F \== Key, constant_field(T, F, Occs, C) ), Dropped),
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
	findall(A, ( member(A-L, Actions0), string(L), rhs_action(L, Order, _, insert) ), Ins),
	findall(x, ( member(_-X, Actions0), \+ string(X) ), Others),
	(   Ins = [A], Others == [],
	    \+ ( member(A2-L2, Actions0), A2 \== A, string(L2) ),
	    inserted_fact(A, Order, F), raw_shape(W, F, S, Args),
	    kept_args(S, Args, K), exists_fluent(W, S, K, G),
	    \+ ( member(holds(not(G0), _), Conds0), subsumes_term(G0, G) )
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
